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

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
((FAIL == 0))
