#!/usr/bin/env bash
# Unit tests for check-changelog-parity.sh. --check scenarios build a throwaway
# plugins/ tree; --check-bump scenarios build a real two-commit git history so
# the version-changed-but-changelog-untouched case is exercised end to end. The
# negative cases are the synthetic proof the gate catches an undocumented
# version bump and a versioned-but-changelog-less plugin.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-changelog-parity.sh"

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

mk_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-changelog-parity.sh"
  printf '%s' "${1:-}" >"$dir/scripts/changelog-parity-baseline.txt"
  printf '%s' "$dir"
}

git_init() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t.test
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.autocrlf false
}

mk_plugin() {
  local repo="$1" name="$2" version="$3" changelog="$4"
  mkdir -p "$repo/plugins/$name/.claude-plugin"
  printf '{ "name": "%s", "version": "%s" }\n' "$name" "$version" \
    >"$repo/plugins/$name/.claude-plugin/plugin.json"
  [[ "$changelog" == "yes" ]] && printf '# Changelog\n' >"$repo/plugins/$name/CHANGELOG.md"
}

# ============================ --check (static) =============================

# versioned plugin WITH a changelog -> passes
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check >/dev/null 2>&1); then ok "versioned plugin with CHANGELOG passes --check"; else fail "versioned+changelog wrongly failed"; fi
rm -rf "$repo"

# SYNTHETIC MISSING CHANGELOG: versioned plugin, no changelog -> fails
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 no
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"MISSING CHANGELOG"*"alpha"* ]]; then ok "versioned plugin without CHANGELOG fails --check (synthetic gap caught)"; else fail "missing-changelog not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# grandfathered plugin without a changelog -> passes
repo="$(mk_repo $'alpha\n')"
mk_plugin "$repo" alpha 1.0.0 no
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check >/dev/null 2>&1); then ok "grandfathered missing-changelog passes --check"; else fail "grandfathered plugin wrongly failed"; fi
rm -rf "$repo"

# STALE baseline: grandfathered plugin that DOES have a changelog -> fails
repo="$(mk_repo $'alpha\n')"
mk_plugin "$repo" alpha 1.0.0 yes
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
stale_count="$(printf '%s\n' "$out" | grep -c 'STALE BASELINE')"
if [[ $rc -ne 0 && "$stale_count" == "1" ]]; then ok "stale baseline entry fails --check (reported exactly once)"; else fail "stale baseline: rc=$rc count=$stale_count out='$out'"; fi
rm -rf "$repo"

# ------------------- --check reverse parity (#2131) ----------------------
# The direction no other mode covers: a `## [x.y.z]` heading the manifest never
# reached. --check-bump fires only on a CHANGED manifest version and
# --check-order is satisfied by a correctly ordered list, so a release note
# written ahead of its bump reached main unseen.

# newest heading EQUALS the manifest version -> passes
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check >/dev/null 2>&1); then ok "newest heading equal to the manifest version passes --check"; else fail "equal newest heading wrongly failed"; fi
rm -rf "$repo"

# manifest ABOVE the newest heading -> passes: a bump with no consumer-visible
# change need not write a release note. Locks the check to one direction.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.1.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check >/dev/null 2>&1); then ok "manifest above the newest heading passes --check (a bump need not write a note)"; else fail "manifest-ahead wrongly failed"; fi
rm -rf "$repo"

# SYNTHETIC AHEAD-OF-MANIFEST: the docs-hygiene shape — a `## [0.9.7]` entry
# above a 0.9.6 manifest -> fails, naming both versions.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 0.9.6 yes
printf '# Changelog\n\n## [0.9.7]\n\n## [0.9.6]\n' >"$repo/plugins/alpha/CHANGELOG.md"
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"CHANGELOG AHEAD OF MANIFEST"*"alpha"* && "$out" == *"0.9.7"* && "$out" == *"0.9.6"* ]]; then ok "a heading above the manifest version fails --check (synthetic #2131 shape caught)"; else fail "ahead-of-manifest not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# NUMERIC, NOT LEXICAL: 0.9.0 sorts above 0.10.0 as a string. A manifest at
# 0.10.0 with a 0.9.0 heading must pass, not red-line.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 0.10.0 yes
printf '# Changelog\n\n## [0.9.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check >/dev/null 2>&1); then ok "reverse parity compares numerically, not lexically (0.10.0 manifest, 0.9.0 heading)"; else fail "lexical comparison leaked into --check"; fi
rm -rf "$repo"

# UNBRACKETED heading form: the shared extractor reads `## 1.1.0 — date` too, so
# dropping the brackets cannot smuggle a heading past the reverse check.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## 1.1.0 — 2026-08-10\n' >"$repo/plugins/alpha/CHANGELOG.md"
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"CHANGELOG AHEAD OF MANIFEST"*"alpha"* ]]; then ok "an unbracketed heading above the manifest is still caught"; else fail "unbracketed ahead-heading missed: rc=$rc out='$out'"; fi
rm -rf "$repo"

# A changelog with no version heading at all has nothing to compare -> passes.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\nNo releases yet.\n' >"$repo/plugins/alpha/CHANGELOG.md"
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check >/dev/null 2>&1); then ok "a changelog with no version heading passes --check"; else fail "heading-less changelog wrongly failed"; fi
rm -rf "$repo"

# NON-SEMVER MANIFEST VERSION: must refuse loudly (exit 2) rather than feed
# garbage to the arithmetic sort key, same as --check-bump.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.two.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"non-SemVer"*"1.two.0"* ]]; then ok "--check refuses a non-SemVer manifest version loudly (exit 2)"; else fail "--check did not refuse malformed version: rc=$rc out='$out'"; fi
rm -rf "$repo"

# ...and refuses it EVEN WITH NO HEADING to compare against: an uncomparable
# manifest version is a defect in its own right, so the guard must not hide
# behind the presence of a release note.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.two.0 yes
printf '# Changelog\n\nNo releases yet.\n' >"$repo/plugins/alpha/CHANGELOG.md"
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"non-SemVer"*"1.two.0"* ]]; then ok "--check refuses a non-SemVer manifest version with a heading-less changelog too"; else fail "malformed version rode through behind a missing heading: rc=$rc out='$out'"; fi
rm -rf "$repo"

# SEMVER BUILD METADATA above the manifest -> caught. Manifests and --check-bump
# both accept `1.0.1+build.1`, so a heading extractor that dropped the tail would
# leave exactly that class unchecked — a gate that silently checks nothing.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.1+build.1]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"CHANGELOG AHEAD OF MANIFEST"*"1.0.1+build.1"* ]]; then ok "a build-metadata heading above the manifest is caught"; else fail "build-metadata heading slipped past the reverse check: rc=$rc out='$out'"; fi
rm -rf "$repo"

# ...and the matching manifest passes: the tail is stripped before comparing, so
# an equal-core pair is not a false failure.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.1+build.1 yes
printf '# Changelog\n\n## [1.0.1+build.1]\n' >"$repo/plugins/alpha/CHANGELOG.md"
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check >/dev/null 2>&1); then ok "a build-metadata heading equal to the manifest passes --check"; else fail "equal build-metadata pair wrongly failed"; fi
rm -rf "$repo"

# FENCED EXAMPLE: a column-zero heading with a high version inside a ``` block is
# not rendered markdown, so it must not be read as the newest release. Without
# fence tracking this is a false FAIL in a required gate with no baseline escape.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
# shellcheck disable=SC2016  # single quotes are deliberate: the backtick fence and \n are literal changelog bytes
printf '# Changelog\n\nHeadings look like this:\n\n```\n## [9.9.9]\n```\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "a fenced example heading is not read as the newest release"; else fail "fenced example wrongly red-lined --check: rc=$rc out='$out'"; fi
rm -rf "$repo"

# HTML-COMMENT EXAMPLE: same, inside a multi-line <!-- --> block.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n<!--\n## [9.9.9]\n-->\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "a heading inside an HTML comment is not read as the newest release"; else fail "commented heading wrongly red-lined --check: rc=$rc out='$out'"; fi
rm -rf "$repo"

# ...and the same suppression applies to --check-order, which reads changelogs
# through the same tracker: a fenced out-of-order example must not be misordered.
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
# shellcheck disable=SC2016  # single quotes are deliberate: the backtick fence and \n are literal changelog bytes
printf '# Changelog\n\n## [2.0.0]\n\n```\n## [0.1.0]\n```\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check-order >/dev/null 2>&1); then ok "a fenced example heading is invisible to --check-order too"; else fail "fenced example wrongly red-lined --check-order"; fi
rm -rf "$repo"

# ============================ --check-bump (diff) =========================

# version changed AND changelog has the new version's entry -> passes
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" >/dev/null 2>&1); then ok "bump + '## [x.y.z]' entry passes --check-bump"; else fail "bump+entry wrongly failed"; fi
rm -rf "$repo"

# LARGE CHANGELOG (SIGPIPE regression, #2130): the new entry sits near the top
# of a changelog far larger than the pipe buffer — the shape every mature
# changelog has. A has_heading reader that exits on first match kills
# rendered_lines mid-write with SIGPIPE, and pipefail turns the FOUND heading
# into a false UNDOCUMENTED BUMP. The small fixtures above fit in one buffer
# and cannot catch this; the padding here (~260 KB) exceeds the pipe CAPACITY,
# so against an early-exiting reader the writer blocks mid-write and the
# SIGPIPE is deterministic, not a winnable race — but only under gawk (the CI
# runner's awk): mawk survives the closed pipe and passes regardless, so on a
# machine where `awk` resolves to mawk this guard would silently prove
# nothing. The run below therefore FORCES gawk via a PATH shim, and skips
# loudly when gawk is absent rather than reporting a pass that exercised
# nothing. The fix itself is engine-independent — the reader consumes to EOF,
# so no writer can ever take SIGPIPE under any awk.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
{
  printf '# Changelog\n\n## [1.1.0]\n\n'
  for ((i = 0; i < 4000; i++)); do
    printf '%s\n' '- a release note line padding the file well past any pipe or stdio buffer'
  done
  printf '\n## [1.0.0]\n'
} >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
if command -v gawk >/dev/null 2>&1; then
  mkdir -p "$repo/bin"
  printf '#!/bin/sh\nexec gawk "$@"\n' >"$repo/bin/awk"
  chmod +x "$repo/bin/awk"
  out="$(cd "$repo" && PATH="$repo/bin:$PATH" bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then ok "large changelog with the new entry near the top passes under gawk (no SIGPIPE misread under pipefail)"; else fail "large-changelog bump wrongly failed under gawk: rc=$rc out='$out'"; fi
else
  echo "SKIP: SIGPIPE regression fixture requires gawk; under mawk an early-exiting reader survives the closed pipe, so without gawk this case cannot distinguish fixed from unfixed." >&2
fi
rm -rf "$repo"

# SYNTHETIC MALFORMED ENTRY: version present but as an UNBRACKETED heading
# (## 1.1.0) -> FORMAT error naming the found heading, NOT "UNDOCUMENTED BUMP".
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## 1.1.0 — 2026-07-20\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"CHANGELOG FORMAT"*"alpha"* && "$out" == *"## 1.1.0"* && "$out" != *"UNDOCUMENTED BUMP"* ]]; then ok "bump + unbracketed heading -> FORMAT error (not UNDOCUMENTED)"; else fail "format-split not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# NEWLY-ADDED ENTRY: base carries an earlier `## [1.0.0]`; the bump ADDS
# `## [1.1.0]` (present at head, absent at base) -> passes. Proves the pass
# path accepts a genuinely new release note.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" >/dev/null 2>&1); then ok "bump adding a NEW '## [x.y.z]' entry (absent at base) passes --check-bump"; else fail "newly-added entry wrongly failed"; fi
rm -rf "$repo"

# PRE-EXISTING ENTRY: the `## [1.1.0]` heading already exists in the base
# changelog; the bump only edits plugin.json, adding no new release note ->
# fails as PRE-EXISTING (not UNDOCUMENTED). Proves the gate closes the fail-open
# where a bump reuses a heading that predates the change set.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.1.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"PRE-EXISTING CHANGELOG ENTRY"*"alpha"* && "$out" != *"UNDOCUMENTED BUMP"* ]]; then ok "bump reusing a base-pre-existing '## [x.y.z]' entry fails --check-bump"; else fail "preexisting-entry not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# SEMVER BUILD METADATA: a version like 1.0.1+build.1 must round-trip — the
# fixed-string heading match must not interpret "+" as a regex quantifier, so
# a correctly-added `## [1.0.1+build.1]` entry passes the gate.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.0.1+build.1" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.0.1+build.1]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" >/dev/null 2>&1); then ok "SemVer build-metadata version with a proper entry passes (no regex leak)"; else fail "build-metadata version wrongly failed"; fi
rm -rf "$repo"

# PROSE MENTION: the bumped version's `## [1.1.0]` appears only inline and on an
# indented line, never as a column-zero heading -> fails as UNDOCUMENTED. Proves
# the heading match is anchored, so an inline or indented mention neither
# satisfies nor falsely pre-exists the release entry. (The fenced-block case,
# where `## [1.1.0]` sits at column zero inside ```, is covered separately.)
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.0.0]\n\nNext release will be titled "## [1.1.0]" per convention.\n  ## [1.1.0] (example, indented, not a heading)\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNDOCUMENTED BUMP"*"alpha"* && "$out" != *"PRE-EXISTING"* ]]; then ok "version string in prose/indented example does not satisfy the anchored heading match"; else fail "unanchored-mention not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# FENCED-BLOCK EXAMPLE: the bumped version's `## [1.1.0]` sits at column zero but
# INSIDE a ``` fenced block, never as a real heading -> fails as UNDOCUMENTED.
# Proves the heading match tracks fence state (column-zero alone is not enough).
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
# shellcheck disable=SC2016  # single quotes are deliberate: the backtick fence and \n are literal changelog bytes, not shell expansions
printf '# Changelog\n\nExample of a heading:\n\n```\n## [1.1.0]\n```\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNDOCUMENTED BUMP"*"alpha"* && "$out" != *"PRE-EXISTING"* ]]; then ok "fenced-code example heading (column zero inside a fence) does not satisfy --check-bump"; else fail "fenced-block heading wrongly satisfied gate: rc=$rc out='$out'"; fi
rm -rf "$repo"

# MISMATCHED INNER FENCE DELIMITER: a backtick fence contains a ~~~ content line
# (a different delimiter, so NOT a close per CommonMark); a `## [1.1.0]` after it
# is still inside the backtick fence -> fails as UNDOCUMENTED. Proves fence
# tracking closes only on the opening delimiter, not any fence-looking line.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
# shellcheck disable=SC2016  # single quotes are deliberate: the backtick/tilde fences and \n are literal changelog bytes
printf '# Changelog\n\n```\n~~~\n## [1.1.0]\n```\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNDOCUMENTED BUMP"*"alpha"* && "$out" != *"PRE-EXISTING"* ]]; then ok "mismatched inner fence delimiter (tilde line inside a backtick fence) does not prematurely close"; else fail "fence delimiter mismatch wrongly toggled: rc=$rc out='$out'"; fi
rm -rf "$repo"

# NON-CLOSING FENCE LINES: a backtick fence contains a ```not-a-close line (text
# after the run) and a four-space-indented ``` line (indented code column, not a
# fence per CommonMark); neither closes, so a `## [1.1.0]` after them is still
# fenced -> fails as UNDOCUMENTED. Proves a close requires a whitespace-only
# suffix and at-most-three-space indentation.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
# shellcheck disable=SC2016  # single quotes are deliberate: fence lines are literal changelog bytes
printf '# Changelog\n\n```\n```not-a-close\n    ```\n## [1.1.0]\n```\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNDOCUMENTED BUMP"*"alpha"* && "$out" != *"PRE-EXISTING"* ]]; then ok "non-closing fence lines (text suffix, four-space indent) do not close a fence"; else fail "non-closing fence line wrongly closed the fence: rc=$rc out='$out'"; fi
rm -rf "$repo"

# HTML-COMMENT HEADING: the bumped version's heading appears only inside a
# multi-line <!-- --> comment -> not rendered Markdown -> fails as UNDOCUMENTED.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n<!--\n## [1.1.0]\n-->\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNDOCUMENTED BUMP"*"alpha"* && "$out" != *"PRE-EXISTING"* ]]; then ok "heading inside an HTML comment does not satisfy --check-bump"; else fail "HTML-comment heading wrongly satisfied gate: rc=$rc out='$out'"; fi
rm -rf "$repo"

# SYNTHETIC UNDOCUMENTED BUMP: version changed, changelog edited but WITHOUT an
# entry for the new version (unrelated edit) -> fails. Proves the gate checks
# the version's own entry, not merely that the file was touched.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog (typo fix)\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNDOCUMENTED BUMP"*"alpha"* ]]; then ok "bump + unrelated changelog edit (no new-version entry) fails --check-bump"; else fail "unrelated-edit bump not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# SYNTHETIC UNDOCUMENTED BUMP: version changed, changelog untouched -> fails
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNDOCUMENTED BUMP"*"alpha"* ]]; then ok "bump without changelog fails --check-bump (synthetic undocumented bump caught)"; else fail "undocumented bump not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# version unchanged -> passes (no bump, nothing to document)
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf 'unrelated\n' >"$repo/plugins/alpha/README.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm noop
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" >/dev/null 2>&1); then ok "unchanged version passes --check-bump"; else fail "unchanged version wrongly failed"; fi
rm -rf "$repo"

# new plugin absent at base -> --check-bump skips it (static --check owns it)
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
mk_plugin "$repo" beta 1.0.0 no
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm add-beta
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" >/dev/null 2>&1); then ok "new plugin skipped by --check-bump"; else fail "new plugin wrongly failed --check-bump"; fi
rm -rf "$repo"

# =================== --check-bump branch staleness (#693) ================

# BRANCH STALENESS (untouched plugin advanced only on the base ref): main bumps
# alpha 1.0.0 -> 1.1.0 while the PR branch, forked before that bump, never touches
# alpha (it edits only beta). The base ref sees alpha at 1.1.0 and the stale branch
# at 1.0.0, but alpha is outside the branch's own diff, so it must NOT be flagged
# -- no re-merge treadmill. Proves the bump check is scoped to base...HEAD.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
mk_plugin "$repo" beta 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/beta/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
# main advances alpha (a plugin the PR never touches)
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main bumps alpha'
main="$(git -C "$repo" rev-parse HEAD)"
# PR branch forks from base and edits only beta's changelog (alpha left stale)
git -C "$repo" checkout -q -b pr "$fork"
printf '# Changelog\n\ntypo fix\n\n## [1.0.0]\n' >"$repo/plugins/beta/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr edits beta only'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "untouched plugin advanced only on the base ref is not flagged (branch staleness scoped out)"; else fail "branch-staleness wrongly flagged: rc=$rc out='$out'"; fi
rm -rf "$repo"

# MANIFEST-SCOPED (cosmetic touch does not pull a main-only advance into scope):
# main advances alpha; the PR touches only alpha's README, never alpha's manifest.
# Plugin-root scoping would drag alpha back in and red-line it; manifest scoping
# leaves it out -> rc=0. Locks the filter granularity to the manifest path.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main bumps alpha'
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr "$fork"
printf 'docs\n' >"$repo/plugins/alpha/README.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr edits alpha README only'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "cosmetic touch under a plugin dir does not pull a main-only advance into scope (manifest-scoped)"; else fail "manifest-scoping regressed to plugin-root: rc=$rc out='$out'"; fi
rm -rf "$repo"

# COUNTERPART (a plugin the branch DID bump is still checked): main advances alpha
# (untouched by the PR) AND the PR bumps beta's manifest without adding beta's
# entry. alpha is scoped out; beta -- whose manifest the change set touched -- must
# still fail UNDOCUMENTED. Proves diff-scoping narrows the check, not disables it.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
mk_plugin "$repo" beta 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/beta/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main bumps alpha'
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr "$fork"
printf '{ "name": "beta", "version": "2.0.0" }\n' >"$repo/plugins/beta/.claude-plugin/plugin.json"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr bumps beta, no entry'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNDOCUMENTED BUMP"*"beta"* && "$out" != *"alpha"* ]]; then ok "a plugin the branch bumped is still checked while the main-only advance is scoped out"; else fail "diff-scoping incorrectly scoped: rc=$rc out='$out'"; fi
rm -rf "$repo"

# ================ --check-bump version monotonicity (#2056) ==============

# VERSION REGRESSION (stale brief, the #1989 fleet shape): the branch, forked at
# 0.21.9, bumps alpha to 0.21.10 WITH a proper new entry, but main has moved to
# 0.25.0. Parity alone reads the pair as valid; monotonicity must fail it — the
# merge would move the version backward.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 0.21.9 yes
printf '# Changelog\n\n## [0.21.9]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "0.25.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [0.25.0]\n\n## [0.21.9]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main advances alpha to 0.25.0'
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr "$fork"
printf '{ "name": "alpha", "version": "0.21.10" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [0.21.10]\n\n## [0.21.9]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr bumps alpha to 0.21.10 off a stale base'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"VERSION REGRESSION"*"alpha"* && "$out" != *"UNDOCUMENTED"* && "$out" != *"PRE-EXISTING"* ]]; then ok "bump below the base ref's current version fails as VERSION REGRESSION despite valid parity"; else fail "version regression not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# VERSION COLLISION (two branches staged one number): the branch bumps alpha
# 1.0.0 -> 1.1.0 with a proper entry, but main already merged its own 1.1.0.
# head==base-tip previously read as "not bumped" and skipped silently; the fork
# comparison must see the branch's own bump and fail the collision loudly.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main merges its own 1.1.0'
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr "$fork"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr also bumps to 1.1.0'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"VERSION COLLISION"*"alpha"* && "$out" != *"UNDOCUMENTED"* ]]; then ok "bump equal to the base ref's current version fails as VERSION COLLISION (not skipped as not-bumped)"; else fail "version collision not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# SYNTHETIC PR MERGE COMMIT (pull_request checkout): same collision as above,
# but HEAD is a merge of the PR branch into the base tip — the shape CI checks
# out. merge-base(base, HEAD) degenerates to the base tip there, which read the
# collision as not-bumped; the gate must fork from HEAD^2 instead.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog

## [1.0.0]
' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }
' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog

## [1.1.0]

## [1.0.0]
' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main merges its own 1.1.0'
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr "$fork"
printf '{ "name": "alpha", "version": "1.1.0" }
' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog

## [1.1.0]

## [1.0.0]
' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr also bumps to 1.1.0'
git -C "$repo" checkout -q "$main"
git -C "$repo" checkout -q -b synthetic
git -C "$repo" merge -q --no-ff -m 'synthetic PR merge' pr >/dev/null 2>&1
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"VERSION COLLISION"*"alpha"* ]]; then ok "collision detected from a synthetic PR merge-commit checkout (fork from HEAD^2)"; else fail "synthetic-merge collision not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# NON-SEMVER MANIFEST VERSION: a malformed version must refuse loudly, never
# reach the arithmetic sort key.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog

## [1.0.0]
' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr
printf '{ "name": "alpha", "version": "1.two.0" }
' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog

## [1.two.0]

## [1.0.0]
' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr ships a malformed version'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"non-SemVer"*"1.two.0"* ]]; then ok "malformed manifest version refuses loudly before the sort key"; else fail "malformed version not refused: rc=$rc out='$out'"; fi
rm -rf "$repo"

# FORWARD PAST AN ADVANCED BASE: main moved alpha to 1.1.0 after the fork; the
# branch bumps past it to 1.2.0 with a proper new entry -> passes. Proves
# monotonicity compares against the base ref's CURRENT version and lets a
# correctly renumbered branch through.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main bumps alpha to 1.1.0'
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr "$fork"
printf '{ "name": "alpha", "version": "1.2.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.2.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr bumps past the advance to 1.2.0'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "bump strictly above the base ref's advanced version passes --check-bump"; else fail "forward bump past an advanced base wrongly failed: rc=$rc out='$out'"; fi
rm -rf "$repo"

# NUMERIC, NOT LEXICAL: 0.10.0 outranks 0.9.0 even though it sorts below it as a
# string. A correctly documented 0.9.0 -> 0.10.0 bump must pass, not red-line as
# a regression.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 0.9.0 yes
printf '# Changelog\n\n## [0.9.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "0.10.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [0.10.0]\n\n## [0.9.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "0.9.0 -> 0.10.0 passes (monotonicity is numeric, not lexical)"; else fail "cross-segment bump wrongly failed: rc=$rc out='$out'"; fi
rm -rf "$repo"

# COSMETIC MANIFEST EDIT ON A STALE BRANCH: main bumps alpha 1.0.0 -> 1.1.0; the
# branch touches alpha's MANIFEST (description only) but never its version.
# head!=base-tip, yet the branch bumped nothing — the fork comparison must scope
# it out, not red-line it as a regression and force a merge-from-main.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n## [1.0.0]\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main bumps alpha'
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr "$fork"
printf '{ "name": "alpha", "version": "1.0.0", "description": "d" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr edits alpha manifest, no version change'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$main" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "manifest edit without a version change on a stale branch is not flagged (fork-scoped, no regression false positive)"; else fail "cosmetic manifest edit wrongly flagged: rc=$rc out='$out'"; fi
rm -rf "$repo"

# NO COMMON ANCESTOR (git diff cannot compute a diff): base is a resolvable
# commit but shares no history with HEAD (an orphan root), so 'git diff
# base...HEAD' fails ("fatal: no merge base", exit 128). The gate must fail LOUD
# (exit 2), not silently pass: an empty result from a FAILED git invocation would
# skip every plugin and let this required merge gate exit 0 without checking
# anything (fail-open). This is distinct from a legitimate "zero files changed"
# diff, which git computes successfully and which must still pass (covered above).
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
# Orphan branch: a second root commit with no ancestor in common with base.
git -C "$repo" checkout -q --orphan orphan
git -C "$repo" rm -rq --cached . >/dev/null 2>&1 || true
mk_plugin "$repo" alpha 1.1.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'orphan root'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump "$base" 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"failed"* ]]; then ok "no common ancestor -> git diff fails -> gate fails loud (exit 2), never silent pass"; else fail "no-common-ancestor did not fail loud: rc=$rc out='$out'"; fi
rm -rf "$repo"

# unresolvable base ref -> exit 2
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump does-not-exist >/dev/null 2>&1)
if [[ $? -eq 2 ]]; then ok "unresolvable base ref -> exit 2"; else fail "bad base ref did not exit 2"; fi
rm -rf "$repo"

# --check-bump with no base ref -> exit 2 (consistent with other usage errors)
repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 yes
(cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump >/dev/null 2>&1)
if [[ $? -eq 2 ]]; then ok "--check-bump without base ref -> exit 2"; else fail "missing base ref did not exit 2"; fi
rm -rf "$repo"

# bad usage -> exit 2
repo="$(mk_repo)"
(cd "$repo" && bash scripts/check-changelog-parity.sh --nonsense >/dev/null 2>&1)
if [[ $? -eq 2 ]]; then ok "bad mode -> exit 2"; else fail "bad mode did not exit 2"; fi
rm -rf "$repo"

# --- --check-order -----------------------------------------------------------
# Regression cover for the defect that shipped: a stale-based entry whose number
# was already behind by the time it merged, in a file no other mode reads.
write_changelog() { # $1 path, $2... headings
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  printf '# Changelog\n\n' >"$path"
  local h
  for h in "$@"; do printf '%s\n\nsome note\n\n' "$h" >>"$path"; done
}

repo="$(mk_repo)"
mk_plugin "$repo" alpha 1.0.0 no
write_changelog "$repo/plugins/alpha/CHANGELOG.md" '## [3.0.0]' '## [2.0.0]' '## [1.0.0]'
if out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"; then ok "descending plugin changelog passes"; else fail "descending changelog rejected: $out"; fi

write_changelog "$repo/plugins/alpha/CHANGELOG.md" '## [3.0.0]' '## [1.5.0]' '## [2.0.0]'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"MISORDERED CHANGELOG"* ]]; then ok "a version below a later one is caught"; else fail "misordering not caught: rc=$rc $out"; fi
if [[ "$out" == *"2.0.0 (below 1.5.0)"* ]]; then ok "the offending pair is named"; else fail "offender not named: $out"; fi

write_changelog "$repo/plugins/alpha/CHANGELOG.md" '## [2.0.0]' '## [2.0.0]' '## [1.0.0]'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"DUPLICATE CHANGELOG VERSION"* ]]; then ok "two branches staging one version is caught"; else fail "duplicate not caught: rc=$rc $out"; fi

# The exact shape that shipped, in the exact file class that shipped it: a
# CONVENTION changelog, which is unversioned by any manifest and therefore
# invisible to --check and --check-bump.
write_changelog "$repo/plugins/alpha/CHANGELOG.md" '## [1.0.0]'
write_changelog "$repo/docs/conventions/demo/CHANGELOG.md" \
  '## 6.0.0 — 2026-07-29' '## 3.1.1 — 2026-07-29' '## 5.0.0 — 2026-07-29' '## 4.0.0 — 2026-07-27'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"docs/conventions/demo/CHANGELOG.md"* ]]; then ok "unbracketed CONVENTION changelogs are in scope"; else fail "convention changelog not checked: rc=$rc $out"; fi

# A single-entry changelog has no order to violate.
write_changelog "$repo/docs/conventions/demo/CHANGELOG.md" '## 1.0.0 — 2026-01-01'
if out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"; then ok "a single-entry changelog passes"; else fail "single entry rejected: $out"; fi

# Numeric, not lexical: 10.0.0 sorts ABOVE 9.0.0.
write_changelog "$repo/docs/conventions/demo/CHANGELOG.md" '## 10.0.0 — 2026-02-01' '## 9.0.0 — 2026-01-01'
if out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"; then ok "version order is numeric, not lexical (10.0.0 > 9.0.0)"; else fail "lexical comparison leaked in: $out"; fi

# Two-component `## 1.2` headings: several convention changelogs use them, and
# requiring a patch component made the gate silently check NOTHING there.
write_changelog "$repo/docs/conventions/demo/CHANGELOG.md" '## 1.2 — 2026-02-01' '## 1.1 — 2026-01-15' '## 1.0 — 2026-01-01'
if out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"; then ok "descending two-component versions pass"; else fail "two-component descending rejected: $out"; fi

write_changelog "$repo/docs/conventions/demo/CHANGELOG.md" '## 1.2 — 2026-02-01' '## 1.0 — 2026-01-01' '## 1.1 — 2026-01-15'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"MISORDERED CHANGELOG"* ]]; then ok "misordered two-component versions are caught"; else fail "two-component misordering missed: rc=$rc $out"; fi

# Mixed widths in one file must compare correctly: 1.10 outranks 1.9.
write_changelog "$repo/docs/conventions/demo/CHANGELOG.md" '## 1.10 — 2026-02-01' '## 1.9.1 — 2026-01-15' '## 1.9 — 2026-01-01'
if out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-order 2>&1)"; then ok "two- and three-component versions compare correctly together"; else fail "mixed-width comparison wrong: $out"; fi
rm -rf "$repo"

# ===================== --check-preserved (#2264) =========================
# The gap: every other mode polices what a change set ADDS. A merge-forward that
# writes the new release under the PREVIOUS release's heading — absorbing it —
# deletes a released section with no conflict marker left behind, and all three
# pass. The first case below asserts that gap explicitly (the other three modes
# green on the very tree --check-preserved red-lines) so a future edit cannot
# quietly make this mode redundant without the suite noticing.

# ABSORBED PREDECESSOR: base carries 0.51.8 and 0.51.7; head bumps to 0.51.9 and
# folds 0.51.8's note into the new section, deleting its heading.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 0.51.8 yes
printf '# Changelog\n\n## [0.51.8]\n\n- eight\n\n## [0.51.7]\n\n- seven\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "0.51.9" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [0.51.9]\n\n- nine\n- eight\n\n## [0.51.7]\n\n- seven\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'absorb 0.51.8 into 0.51.9'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"DELETED CHANGELOG ENTRY"*"plugins/alpha/CHANGELOG.md"* && "$out" == *"0.51.8"* ]]; then ok "an absorbed predecessor section fails --check-preserved, naming the vanished version"; else fail "absorbed section not caught: rc=$rc out='$out'"; fi
for other in "--check-bump $base" "--check-order" "--check"; do
  # shellcheck disable=SC2086  # deliberate split: the mode and its optional base ref
  if (cd "$repo" && bash scripts/check-changelog-parity.sh $other >/dev/null 2>&1); then ok "the absorbed-section tree still passes '$other' (the gap --check-preserved exists to close)"; else fail "'$other' unexpectedly fired on the absorbed-section tree — the gap assertion is stale"; fi
done
rm -rf "$repo"

# RELABELLED PREDECESSOR: the same bad resolution renames 0.51.8's heading to
# 0.51.9 instead of adding one. That IS a deletion of 0.51.8, and the failure
# message must say so, so the author recognises what their resolve did.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 0.51.8 yes
printf '# Changelog\n\n## [0.51.8]\n\n- eight\n\n## [0.51.7]\n\n- seven\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "0.51.9" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [0.51.9]\n\n- eight\n\n## [0.51.7]\n\n- seven\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'relabel 0.51.8 as 0.51.9'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"0.51.8"* && "$out" == *"RELABELLING"* && "$out" == *"above the entry that replaced it"* ]]; then ok "a relabelled heading fails --check-preserved and the message names relabelling as a cause"; else fail "relabelled heading not caught or not explained: rc=$rc out='$out'"; fi
rm -rf "$repo"

# LEGITIMATE BUMP: adds a heading, preserves every predecessor -> passes. The
# discriminating half of the pair above; a check that never passes is as useless
# as one that never fires.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 0.51.8 yes
printf '# Changelog\n\n## [0.51.8]\n\n- eight\n\n## [0.51.7]\n\n- seven\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "0.51.9" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [0.51.9]\n\n- nine\n\n## [0.51.8]\n\n- eight\n\n## [0.51.7]\n\n- seven\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "a bump that adds a heading and preserves its predecessors passes --check-preserved"; else fail "legitimate bump wrongly failed: rc=$rc out='$out'"; fi
rm -rf "$repo"

# STALE BRANCH THAT NEVER INTEGRATED: main adds `## [1.1.0]` after the fork; the
# branch edits its OWN changelog and never merges main forward. Compared against
# the base TIP, every heading main added would read as deleted — a false positive
# on a required gate. The fork point is the only correct comparison.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
fork="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.1.0]\n\n- main note\n\n## [1.0.0]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'main bumps alpha'
main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b pr "$fork"
printf '# Changelog\n\n## [1.0.0]\n\n- one\n- a wording fix\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'pr edits its changelog, never integrates main'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$main" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "a stale branch that never integrated main is not flagged (fork-point comparison, no false positive)"; else fail "stale branch wrongly flagged: rc=$rc out='$out'"; fi
rm -rf "$repo"

# CHANGELOG NEW IN THIS CHANGE SET: absent at the fork point, so there is nothing
# to preserve. (`git cat-file -e` cannot express this — it exits 128 for a
# missing path exactly as it does for an unusable rev — so this case is the guard
# on the existence probe.)
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 no
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '# Changelog\n\n## [1.0.0]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'add a changelog'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "a changelog added by this change set passes --check-preserved (nothing to preserve)"; else fail "newly added changelog wrongly failed: rc=$rc out='$out'"; fi
rm -rf "$repo"

# PLUGIN REMOVED: the changelog goes with its whole directory. That is a removal,
# not an absorbed section.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
mk_plugin "$repo" beta 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
rm -rf "$repo/plugins/alpha"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'remove the alpha plugin'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "removing a plugin outright passes --check-preserved (its whole directory went with it)"; else fail "plugin removal wrongly flagged: rc=$rc out='$out'"; fi
rm -rf "$repo"

# CHANGELOG DELETED, PLUGIN KEPT: the extreme form of the same defect — every
# released heading vanishes at once, and the plugin is still there.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
rm -f "$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'delete the changelog, keep the plugin'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"DELETED CHANGELOG ENTRY"*"1.0.0"* ]]; then ok "deleting a changelog while its plugin survives fails --check-preserved"; else fail "whole-file deletion not caught: rc=$rc out='$out'"; fi
# ...and gets the remediation for THAT failure: "restore the heading above the
# entry that replaced it" names an entry that does not exist when the whole file
# is gone.
if [[ "$out" == *"changelog itself was deleted"* && "$out" != *"above the entry that replaced it"* ]]; then ok "whole-file deletion gets the restore-the-file remediation, not the absorbed-heading one"; else fail "whole-file deletion printed the wrong remediation: out='$out'"; fi
rm -rf "$repo"

# YANKED RELEASE: Keep a Changelog keeps the heading and marks it `[YANKED]`
# rather than deleting it, so the correct treatment of a pulled release must
# PASS. This is why the mode ships no exemption list.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.0.1" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.0.1]\n\n- revert\n\n## [1.0.0] - 2026-01-01 [YANKED]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'yank 1.0.0'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "marking a release '[YANKED]' preserves its heading and passes --check-preserved"; else fail "yanked-release marking wrongly failed: rc=$rc out='$out'"; fi
rm -rf "$repo"

# REFORMATTED HEADING: bracketed -> unbracketed names the same version. Matching
# is on the VERSION, so a format change is not a deletion (--check-bump owns the
# format concern).
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '# Changelog\n\n## 1.0.0 — 2026-01-01\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'reformat the heading'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "reformatting a heading to another accepted form is not a deletion"; else fail "heading reformat wrongly flagged: rc=$rc out='$out'"; fi
rm -rf "$repo"

# HEADINGLESS CHANGELOG: the shared extractor's `grep -oE` exits 1 when a file
# declares no version heading at all. Under pipefail that status must NOT be read
# as a failed check — a false positive on every prose-only changelog.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '# Changelog\n\nNothing released yet.\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'edit a headingless changelog'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "a changelog with no version headings passes --check-preserved (grep's no-match status is not an error)"; else fail "headingless changelog wrongly failed: rc=$rc out='$out'"; fi
rm -rf "$repo"

# FENCED EXAMPLE HEADING: what looks like a heading inside a code fence is not
# one, so removing it is not a deletion. The shared extractor owns this.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
printf '# Changelog\n\n## [1.0.0]\n\n~~~\n## [9.9.9]\n~~~\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '# Changelog\n\n## [1.0.0]\n\n- one\n' >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'drop the fenced example'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "removing a fenced example heading is not a deletion"; else fail "fenced example wrongly counted as a released heading: rc=$rc out='$out'"; fi
rm -rf "$repo"

# CONVENTION CHANGELOG: unversioned by any manifest, so --check and --check-bump
# never look at it. Absorption is just as possible there, and --check-preserved
# sweeps the same two roots --check-order does.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
mkdir -p "$repo/docs/conventions/demo"
printf '# Changelog\n\n## 2.0.0 — 2026-01-02\n\n- two\n\n## 1.0.0 — 2026-01-01\n\n- one\n' >"$repo/docs/conventions/demo/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '# Changelog\n\n## 3.0.0 — 2026-01-03\n\n- three\n- two\n\n## 1.0.0 — 2026-01-01\n\n- one\n' >"$repo/docs/conventions/demo/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'absorb 2.0.0 into 3.0.0'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"docs/conventions/demo/CHANGELOG.md"* && "$out" == *"2.0.0"* ]]; then ok "convention changelogs are in --check-preserved scope"; else fail "convention changelog absorption missed: rc=$rc out='$out'"; fi
rm -rf "$repo"

# LARGE CHANGELOG under gawk (the #2130 shape, applied to this mode): the heading
# lists are read through the same rendered_lines writer, so no reader in this
# path may exit before EOF. Forced gawk for the same reason as the --check-bump
# fixture above — mawk survives a closed pipe and would prove nothing.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
{
  printf '# Changelog\n\n## [1.0.0]\n\n'
  for ((i = 0; i < 4000; i++)); do
    printf '%s\n' '- a release note line padding the file well past any pipe or stdio buffer'
  done
  printf '\n## [0.9.0]\n'
} >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf '{ "name": "alpha", "version": "1.1.0" }\n' >"$repo/plugins/alpha/.claude-plugin/plugin.json"
{
  printf '# Changelog\n\n## [1.1.0]\n\n- one one\n\n## [1.0.0]\n\n'
  for ((i = 0; i < 4000; i++)); do
    printf '%s\n' '- a release note line padding the file well past any pipe or stdio buffer'
  done
  printf '\n## [0.9.0]\n'
} >"$repo/plugins/alpha/CHANGELOG.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm bump
if command -v gawk >/dev/null 2>&1; then
  mkdir -p "$repo/bin"
  printf '#!/bin/sh\nexec gawk "$@"\n' >"$repo/bin/awk"
  chmod +x "$repo/bin/awk"
  out="$(cd "$repo" && PATH="$repo/bin:$PATH" bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then ok "a large changelog passes --check-preserved under gawk (no early-exiting reader, no SIGPIPE misread)"; else fail "large-changelog preservation wrongly failed under gawk: rc=$rc out='$out'"; fi
else
  echo "SKIP: the SIGPIPE fixture requires gawk; under mawk a closed pipe is survivable, so this case cannot distinguish fixed from unfixed." >&2
fi
rm -rf "$repo"

# NO COMMON ANCESTOR: same fail-loud discipline as --check-bump — a git read that
# could not be computed must never read as "nothing was deleted" and pass.
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q --orphan orphan
git -C "$repo" rm -rq --cached . >/dev/null 2>&1 || true
mk_plugin "$repo" alpha 1.1.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm 'orphan root'
out="$(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved "$base" 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"failed"* ]]; then ok "--check-preserved fails loud (exit 2) when the diff cannot be computed"; else fail "--check-preserved did not fail loud on a missing common ancestor: rc=$rc out='$out'"; fi
rm -rf "$repo"

# usage errors mirror --check-bump's
repo="$(mk_repo)"
git_init "$repo"
mk_plugin "$repo" alpha 1.0.0 yes
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm base
(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved >/dev/null 2>&1)
if [[ $? -eq 2 ]]; then ok "--check-preserved without a base ref -> exit 2"; else fail "--check-preserved missing base ref did not exit 2"; fi
(cd "$repo" && bash scripts/check-changelog-parity.sh --check-preserved does-not-exist >/dev/null 2>&1)
if [[ $? -eq 2 ]]; then ok "--check-preserved with an unresolvable base ref -> exit 2"; else fail "--check-preserved bad base ref did not exit 2"; fi
rm -rf "$repo"

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
((FAIL == 0))
