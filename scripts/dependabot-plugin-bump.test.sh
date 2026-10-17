#!/usr/bin/env bash
# Fixture tests for dependabot-plugin-bump.sh.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/dependabot-plugin-bump.sh"

# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

repo=""
base=""

mk_repo() {
  local out="$1"
  fixture_tree::build "$out" \
    --sut "$SCRIPT" \
    --sut "$SELF_DIR/check-changelog-parity.sh" \
    --sut "$SELF_DIR/check-changelog-fragments.sh" \
    --sut "$SELF_DIR/new-changelog-fragment.sh" \
    --plugins || return 1
  : >"${!out}/scripts/changelog-parity-baseline.txt"
}

mk_plugin() {
  local r=$1 name=$2 ver=$3
  mkdir -p "$r/plugins/$name/.claude-plugin" "$r/plugins/$name/server"
  printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$name" "$ver" \
    >"$r/plugins/$name/.claude-plugin/plugin.json"
  cat >"$r/plugins/$name/CHANGELOG.md" <<EOF
# Changelog

All notable changes to \`$name\` are documented here.

## [${ver}] - 2026-01-01

### Changed

- Initial fixture release.
EOF
  printf '{}\n' >"$r/plugins/$name/server/package.json"
  printf '{}\n' >"$r/plugins/$name/server/package-lock.json"
}

init_git() {
  local r=$1
  git -C "$r" init -q
  git -C "$r" config user.email "test@example.com"
  git -C "$r" config user.name "test"
  git -C "$r" add -A
  git -C "$r" commit -qm "base"
  git -C "$r" branch -M main
}

# Open a PR branch so main stays behind HEAD (matches CI origin/base vs tip).
begin_pr() {
  local r=$1
  git -C "$r" checkout -qb pr
}

# --- lockfile-only change gets a bump and passes the gate ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
init_git "$repo"
begin_pr "$repo"
printf '{ "lock": 1 }\n' >"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add plugins/alpha/server/package-lock.json
git -C "$repo" commit -qm "build(deps): bump the npm-minor-patch group

Updates \`zod\` from 1.0.0 to 1.0.1"
out="$(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main --pr 99 --title 'build(deps): bump the npm-minor-patch group' 2>&1)"
rc=$?
ver="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
if [[ $rc -eq 0 && "$ver" == "1.0.1" && "$out" == *"alpha 1.0.0 -> 1.0.1"* ]] &&
  grep -q '## \[1.0.1\]' "$repo/plugins/alpha/CHANGELOG.md" &&
  grep -q 'zod.*1.0.0→1.0.1' "$repo/plugins/alpha/CHANGELOG.md"; then
  ok "lockfile-only change bumps and writes changelog"
else
  fail "lockfile bump: rc=$rc ver=$ver out='$out'"
fi
# The inserted entry is separated from the next version heading by a blank line (markdownlint MD022/MD032).
if awk '/^## \[1\.0\.1\]/{seen=1} seen && /^## \[1\.0\.0\]/{exit !(prev=="")} {prev=$0}' "$repo/plugins/alpha/CHANGELOG.md"; then
  ok "inserted entry leaves a blank line before the next heading"
else
  fail "inserted entry runs into the next heading: $(cat "$repo/plugins/alpha/CHANGELOG.md")"
fi
if grep -q 'bundle or dist artifact' "$repo/plugins/alpha/CHANGELOG.md"; then
  fail "a clean tree with no dist change got the bundle note"
else
  ok "a clean tree with no dist change gets no bundle note"
fi
# Gate passes
if (cd "$repo" && bash scripts/check-changelog-parity.sh --check-bump main >/dev/null 2>&1); then
  ok "gate --check-bump passes after bump"
else
  fail "gate failed after bump"
fi
rm -rf "$repo"

# --- second run is a no-op ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
init_git "$repo"
begin_pr "$repo"
printf '{ "lock": 1 }\n' >"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main --pr 1 >/dev/null)
git -C "$repo" add -A && git -C "$repo" commit -qm "bot bump" || true
out="$(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main --pr 1 2>&1)"
rc=$?
ver="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
if [[ $rc -eq 0 && "$ver" == "1.0.1" && "$out" == *"nothing to bump"* ]]; then
  ok "second run is a no-op"
else
  fail "idempotent: rc=$rc ver=$ver out='$out'"
fi
rm -rf "$repo"

# --- two plugins both bumped ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
mk_plugin "$repo" beta 2.0.0
init_git "$repo"
begin_pr "$repo"
echo x >>"$repo/plugins/alpha/server/package-lock.json"
echo y >>"$repo/plugins/beta/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main --pr 7 >/dev/null)
va="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
vb="$(jq -r .version "$repo/plugins/beta/.claude-plugin/plugin.json")"
if [[ "$va" == "1.0.1" && "$vb" == "2.0.1" ]]; then
  ok "two plugins in one PR both get bumped"
else
  fail "multi plugin: alpha=$va beta=$vb"
fi
rm -rf "$repo"

# --- a bundle rebuilt in the working tree, not yet committed, gets the note ---
for shape in modified untracked; do
  mk_repo repo
  mk_plugin "$repo" alpha 1.0.0
  mkdir -p "$repo/plugins/alpha/server/dist"
  [[ "$shape" == modified ]] && echo old >"$repo/plugins/alpha/server/dist/index.min.js"
  init_git "$repo"
  begin_pr "$repo"
  echo x >>"$repo/plugins/alpha/server/package-lock.json"
  git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
  echo new >"$repo/plugins/alpha/server/dist/index.min.js"
  (cd "$repo" && bash scripts/dependabot-plugin-bump.sh main --pr 5 >/dev/null 2>&1)
  if grep -q 'Committed bundle or dist artifact changed' "$repo/plugins/alpha/CHANGELOG.md"; then
    ok "an uncommitted $shape dist file gets the bundle note"
  else
    fail "an uncommitted $shape dist file got no bundle note: $(cat "$repo/plugins/alpha/CHANGELOG.md")"
  fi
  rm -rf "$repo"
done

# --- a plugin in fragment mode gets nothing; a legacy one is still bumped ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
mk_plugin "$repo" beta 2.0.0
printf 'alpha\n' >"$repo/scripts/fragment-plugins.txt"
init_git "$repo"
begin_pr "$repo"
echo x >>"$repo/plugins/alpha/server/package-lock.json"
echo y >>"$repo/plugins/beta/server/package-lock.json"
git -C "$repo" add -A
git -C "$repo" commit -qm "build(deps): bump the npm-minor-patch group

Updates \`zod\` from 1.0.0 to 1.0.1"
out="$(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main --pr 99 --title 'build(deps): bump the npm-minor-patch group' 2>&1)"
rc=$?
vb="$(jq -r .version "$repo/plugins/beta/.claude-plugin/plugin.json")"
if [[ $rc -eq 0 && "$out" == *"alpha is in fragment mode"* && ! -e "$repo/.changes" ]] &&
  [[ -z "$(git -C "$repo" status --porcelain -- plugins/alpha)" ]]; then
  ok "a fragment-mode plugin gets no fragment, version or CHANGELOG edit on the pull request"
else
  fail "fragment-mode alpha was edited: rc=$rc out='$out' status=$(git -C "$repo" status --porcelain)"
fi
# shellcheck disable=SC2016  # the backticks are Markdown in the expected entry
if [[ "$vb" == "2.0.1" ]] && grep -q '## \[2.0.1\]' "$repo/plugins/beta/CHANGELOG.md" &&
  grep -qF -- '- **bump the npm-minor-patch group** (#99).' "$repo/plugins/beta/CHANGELOG.md" &&
  grep -qF -- '  - `zod` 1.0.0→1.0.1' "$repo/plugins/beta/CHANGELOG.md"; then
  ok "a legacy plugin in the same pull request is still bumped, with the same entry"
else
  fail "legacy beta: ver=$vb out='$out' changelog=$(cat "$repo/plugins/beta/CHANGELOG.md")"
fi
rm -rf "$repo"

# --- fragment mode is read from the base, not from a branch that predates a flip ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
init_git "$repo"
begin_pr "$repo"
echo x >>"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
git -C "$repo" checkout -q main
printf 'alpha\n' >"$repo/scripts/fragment-plugins.txt"
git -C "$repo" add -A && git -C "$repo" commit -qm "flip alpha"
git -C "$repo" checkout -q pr
out="$(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main 2>&1)"
rc=$?
ver="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
if [[ $rc -eq 0 && "$ver" == "1.0.0" && "$out" == *"alpha is in fragment mode"* ]]; then
  ok "a plugin the base lists is not bumped on a branch whose own list predates the flip"
else
  fail "base list: rc=$rc ver=$ver out='$out'"
fi
rm -rf "$repo"

# --- a branch older than the fragment library still bumps legacy plugins ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
init_git "$repo"
begin_pr "$repo"
echo x >>"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
rm "$repo/scripts/lib/changelog-fragments.sh"
out="$(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main 2>&1)"
rc=$?
ver="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
if [[ "$ver" == "1.0.1" && "$out" == *"alpha 1.0.0 -> 1.0.1"* ]]; then
  ok "without scripts/lib/changelog-fragments.sh the legacy bump still runs"
else
  fail "missing lib: rc=$rc ver=$ver out='$out'"
fi
rm -rf "$repo"

# --- the workflow's extracted base script reads the base's list through the base's libraries ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
printf 'alpha\n' >"$repo/scripts/fragment-plugins.txt"
init_git "$repo"
begin_pr "$repo"
echo x >>"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
extract="$repo/.git/extract"
mkdir -p "$extract/lib"
cp "$SCRIPT" "$extract/dependabot-plugin-bump.sh"
for lib in changelog-fragments.sh read-list.sh dependabot-entry.sh changed-files.sh; do
  cp "$SELF_DIR/lib/$lib" "$extract/lib/$lib"
done
cp "$SELF_DIR/check-changelog-parity.sh" "$extract/check-changelog-parity.sh"
rm "$repo/scripts/lib/changelog-fragments.sh"
out="$(cd "$repo" && bash "$extract/dependabot-plugin-bump.sh" main 2>&1)"
rc=$?
ver="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
if [[ $rc -eq 0 && "$ver" == "1.0.0" && "$out" == *"alpha is in fragment mode"* ]]; then
  ok "an extracted base script on a branch older than the fragment library skips a listed plugin"
else
  fail "extracted base script: rc=$rc ver=$ver out='$out'"
fi
rm -rf "$repo"

# --- run from main's checkout beside the PR, the bump executes none of the PR's scripts ---
mk_repo repo
mk_repo base
mk_plugin "$repo" alpha 1.0.0
init_git "$repo"
begin_pr "$repo"
marker="$repo/.git/pr-code-ran"
for trap_file in check-changelog-parity.sh lib/changed-files.sh lib/dependabot-entry.sh; do
  printf 'touch %q\nexit 1\n' "$marker" >"$repo/scripts/$trap_file"
done
echo y >>"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
out="$(cd "$repo" && bash "$base/scripts/dependabot-plugin-bump.sh" main 2>&1)"
rc=$?
ver="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
if [[ $rc -eq 0 && "$ver" == "1.0.1" && ! -e "$marker" ]]; then
  ok "a bump run from main's scripts edits the PR tree and runs none of its scripts"
else
  fail "bump from a separate base checkout: rc=$rc ver=$ver marker=$([[ -e $marker ]] && echo present || echo absent) out='$out'"
fi
rm -rf "$repo" "$base"

# --- run from main's checkout, a file missing there stops the bump; the PR's copy never runs ---
for missing in lib/changed-files.sh lib/dependabot-entry.sh lib/changelog-fragments.sh check-changelog-parity.sh; do
  mk_repo repo
  mk_repo base
  mk_plugin "$repo" alpha 1.0.0
  init_git "$repo"
  begin_pr "$repo"
  marker="$repo/.git/pr-code-ran"
  printf 'touch %q\nexit 1\n' "$marker" >"$repo/scripts/$missing"
  echo y >>"$repo/plugins/alpha/server/package-lock.json"
  git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
  rm "$base/scripts/$missing"
  out="$(cd "$repo" && bash "$base/scripts/dependabot-plugin-bump.sh" main 2>&1)"
  rc=$?
  if [[ $rc -eq 2 && ! -e "$marker" && "$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")" == "1.0.0" ]]; then
    ok "main's checkout without $missing exits 2 and runs none of the PR's copy"
  else
    fail "main's checkout without $missing: rc=$rc marker=$([[ -e $marker ]] && echo present || echo absent) out='$out'"
  fi
  rm -rf "$repo" "$base"
done

# --- run from main's checkout, a fragment list the PR plants does not exempt a plugin ---
mk_repo repo
mk_repo base
mk_plugin "$repo" alpha 1.0.0
init_git "$repo"
begin_pr "$repo"
printf 'alpha\n' >"$repo/scripts/fragment-plugins.txt"
echo y >>"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
out="$(cd "$repo" && bash "$base/scripts/dependabot-plugin-bump.sh" main 2>&1)"
rc=$?
ver="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
if [[ $rc -eq 0 && "$ver" == "1.0.1" ]]; then
  ok "a fragment list the PR plants is ignored; main's copy decides"
else
  fail "PR-planted fragment list: rc=$rc ver=$ver out='$out'"
fi
rm -rf "$repo" "$base"

# --- run from main's checkout, a no-op list the PR plants does not satisfy the self-check ---
mk_repo repo
mk_repo base
mk_plugin "$repo" alpha 1.0.0
mk_plugin "$repo" beta 2.0.0
init_git "$repo"
begin_pr "$repo"
# beta: a version-only re-release, which only an entry in the no-op list sanctions.
jq '.version = "2.0.1"' "$repo/plugins/beta/.claude-plugin/plugin.json" >"$repo/.git/beta.json"
mv "$repo/.git/beta.json" "$repo/plugins/beta/.claude-plugin/plugin.json"
awk '/^## \[2\.0\.0\]/ { print "## [2.0.1] - 2026-01-02\n\n### Changed\n\n- Re-release.\n" } { print }' \
  "$repo/plugins/beta/CHANGELOG.md" >"$repo/.git/beta.md"
mv "$repo/.git/beta.md" "$repo/plugins/beta/CHANGELOG.md"
printf 'beta@2.0.1\n' >"$repo/scripts/changelog-no-op-bumps.txt"
echo y >>"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
out="$(cd "$repo" && bash "$base/scripts/dependabot-plugin-bump.sh" main 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"BUMP WITHOUT CHANGE: beta"* ]]; then
  ok "a no-op list the PR plants is ignored; main's copy decides"
else
  fail "PR-planted no-op list: rc=$rc out='$out'"
fi
rm -rf "$repo" "$base"

# --- a symlinked CHANGELOG.md or manifest is refused, and its target is untouched ---
for linked in CHANGELOG.md .claude-plugin/plugin.json; do
  mk_repo repo
  mk_repo base
  mk_plugin "$repo" alpha 1.0.0
  outside="$base/outside-$(basename "$linked")"
  cp "$repo/plugins/alpha/$linked" "$outside"
  ln -sf "$outside" "$repo/plugins/alpha/$linked"
  init_git "$repo"
  begin_pr "$repo"
  echo s >>"$repo/plugins/alpha/server/package-lock.json"
  git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
  before="$(cksum <"$outside")"
  out="$(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main 2>&1)"
  rc=$?
  if [[ $rc -eq 1 && "$out" == *"symlink"* && "$(cksum <"$outside")" == "$before" ]]; then
    ok "a symlinked $linked is refused and its target left alone"
  else
    fail "symlinked $linked: rc=$rc out='$out'"
  fi
  rm -rf "$repo" "$base"
done

# --- no plugin paths: no-op ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
init_git "$repo"
begin_pr "$repo"
echo hi >"$repo/README.md"
git -C "$repo" add README.md && git -C "$repo" commit -qm "docs"
out="$(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main 2>&1)"
rc=$?
ver="$(jq -r .version "$repo/plugins/alpha/.claude-plugin/plugin.json")"
if [[ $rc -eq 0 && "$ver" == "1.0.0" && "$out" == *"nothing to bump"* ]]; then
  ok "no plugin paths is a no-op"
else
  fail "no-op: rc=$rc ver=$ver out='$out'"
fi
rm -rf "$repo"

# --- missing changelog fails closed ---
mk_repo repo
mk_plugin "$repo" alpha 1.0.0
rm -f "$repo/plugins/alpha/CHANGELOG.md"
init_git "$repo"
begin_pr "$repo"
echo z >>"$repo/plugins/alpha/server/package-lock.json"
git -C "$repo" add -A && git -C "$repo" commit -qm "deps"
out="$(cd "$repo" && bash scripts/dependabot-plugin-bump.sh main 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"no CHANGELOG.md"* ]]; then
  ok "missing changelog fails closed"
else
  fail "missing changelog: rc=$rc out='$out'"
fi
rm -rf "$repo"

test_harness::report
