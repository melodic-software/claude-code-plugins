#!/usr/bin/env bash
# Tests for write-changelog-fragments.sh against throwaway git fixtures: a repo
# with plugins alpha (listed in scripts/fragment-plugins.txt) and beta (not
# listed), and a stub scripts/new-changelog-fragment.sh that names fragments the
# way the real one does. Run inside this repository, every fragment written is
# also checked by the real validator in scripts/lib/changelog-fragments.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-changelog-fragments.sh"
REPO_LIB="$SCRIPT_DIR/../../../scripts/lib/changelog-fragments.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# mkrepo [--no-list] — echoes a repo on branch feat/x with alpha and beta
# committed on main and one uncommitted edit to each staged.
mkrepo() {
  local r
  r="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  {
    git init -q -b main "$r"
    git -C "$r" config user.email t@t.t
    git -C "$r" config user.name t
    git -C "$r" config commit.gpgsign false
    git -C "$r" config core.autocrlf false
    for p in alpha beta; do
      mkdir -p "$r/plugins/$p/.claude-plugin"
      printf '{"name": "%s", "version": "1.0.0"}\n' "$p" >"$r/plugins/$p/.claude-plugin/plugin.json"
      echo one >"$r/plugins/$p/file.md"
    done
    mkdir -p "$r/scripts"
    if [[ "${1:-}" != --no-list ]]; then
      printf '# fragment mode\nalpha  # inline comment\n' >"$r/scripts/fragment-plugins.txt"
      cat >"$r/scripts/new-changelog-fragment.sh" <<'STUB'
#!/usr/bin/env bash
set -u
branch="$(git symbolic-ref --quiet --short HEAD)" || exit 2
slug="${branch,,}"
slug="${slug//[^a-z0-9._-]/-}"
n=$(($(find .changes -name '*.md' 2>/dev/null | wc -l) + 1))
path=".changes/$1/$slug-$(printf '%08x' "$n").md"
mkdir -p ".changes/$1"
printf -- '---\nbump: %s\n---\n\n' "$2" >"$path"
echo "$path"
STUB
    fi
    git -C "$r" add -A && git -C "$r" commit -qm base
    git -C "$r" checkout -qb feat/x
    echo two >>"$r/plugins/alpha/file.md"
    echo two >>"$r/plugins/beta/file.md"
    git -C "$r" add -A
  } >/dev/null 2>&1
  printf '%s' "$r"
}

# write <repo> <message> [args...] — run the writer from a subdirectory, so the
# repository-root resolution is exercised too.
write() {
  local r="$1" msg="$2"
  shift 2
  (cd "$r/plugins" && printf '%s' "$msg" | "$WRITER" "$@") 2>&1
}
frag() { cat "$1/$2"; }
nfrag() { find "$1/.changes" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }

# valid <label> <repo> <path> — the real validator accepts the fragment.
valid() {
  [[ -f "$REPO_LIB" ]] || return 0
  local err
  err="$(cd "$2" && bash -c '. "$1" && changelog_fragments::validate "$2"' _ "$REPO_LIB" "$3" 2>&1)"
  assert_exit "$1" 0 "$?"
  assert_eq "$1: no findings" "" "$err"
}

MSG=$'feat(alpha): add the widget\n\nThe widget does one thing.\nIt does it well.\n\nCo-Authored-By: Someone <s@x.y>\nRefs: #12'

# 1. No scripts/fragment-plugins.txt: nothing written, exit 0.
r=$(mkrepo --no-list)
out=$(write "$r" "$MSG")
assert_exit "no list: exit 0" 0 "$?"
assert_eq "no list: no output" "" "$out"
assert_eq "no list: no fragment" 0 "$(nfrag "$r")"

# 2. feat touching a listed and an unlisted plugin: one fragment, for alpha.
r=$(mkrepo)
out=$(write "$r" "$MSG")
assert_exit "feat: exit 0" 0 "$?"
assert_eq "feat: one fragment, for alpha" ".changes/alpha/feat-x-00000001.md" "$out"
assert_eq "feat: nothing for the unlisted plugin" 1 "$(nfrag "$r")"
want=$'---\nbump: minor\n---\n\n### Added\n\n- add the widget\n\n  The widget does one thing.\n  It does it well.'
assert_eq "feat: minor, Added, body indented, trailers dropped" "$want" "$(frag "$r" "$out")"
valid "feat fragment validates" "$r" "$out"

# 3. Type to bump and section.
for row in 'fix(a): x|patch|### Fixed' 'perf: x|patch|### Changed' 'feat!: x|major|### Added' \
  'refactor(a)!: x|major|### Changed' 'docs: x|none|No release needed (docs): x' \
  'chore: x|none|' 'test: x|none|' 'ci: x|none|' 'refactor: x|none|' 'style: x|none|' 'build: x|none|'; do
  IFS='|' read -r subject bump text <<<"$row"
  r=$(mkrepo)
  out=$(write "$r" "$subject")
  assert_contains "$subject: bump" "$(frag "$r" "$out")" "bump: $bump"
  [[ -z "$text" ]] || assert_contains "$subject: body" "$(frag "$r" "$out")" "$text"
  valid "$subject: validates" "$r" "$out"
done
r=$(mkrepo)
out=$(write "$r" $'fix: x\n\nBREAKING CHANGE: the flag is gone')
assert_contains "BREAKING CHANGE footer: major" "$(frag "$r" "$out")" "bump: major"
assert_not_contains "BREAKING CHANGE footer is a trailer, not body" "$(frag "$r" "$out")" "flag is gone"

# 4. A second commit on the branch appends to the branch's fragment and raises
#    the bump only upward; a none commit leaves it alone.
r=$(mkrepo)
out=$(write "$r" "fix: first")
git -C "$r" add -A >/dev/null && git -C "$r" commit -qm "fix: first" >/dev/null
echo three >>"$r/plugins/alpha/file.md" && git -C "$r" add -A
out2=$(write "$r" "feat: second")
assert_eq "same branch: same fragment" "$out" "$out2"
assert_eq "same branch: still one fragment" 1 "$(nfrag "$r")"
assert_contains "same branch: raised to minor" "$(frag "$r" "$out")" "bump: minor"
assert_contains "same branch: first entry kept" "$(frag "$r" "$out")" "- first"
assert_contains "same branch: second entry added" "$(frag "$r" "$out")" $'### Added\n\n- second'
valid "appended fragment validates" "$r" "$out"
out3=$(write "$r" "fix: third")
assert_contains "lower level: bump stays minor" "$(frag "$r" "$out")" "bump: minor"
out4=$(write "$r" "docs: fourth")
assert_eq "none on a released fragment: nothing written" "" "$out4"
assert_not_contains "none on a released fragment: unchanged" "$(frag "$r" "$out")" "fourth"
[[ -n "$out3" ]] || fail "third commit reported its fragment" path ""

# 5. A none fragment followed by a feat becomes a minor fragment with no reason
#    line left before its first section.
r=$(mkrepo)
out=$(write "$r" "docs: first")
write "$r" "feat: second" >/dev/null
assert_eq "none then feat" $'---\nbump: minor\n---\n\n### Added\n\n- second' "$(frag "$r" "$out")"
valid "none then feat validates" "$r" "$out"

# 6. --base fills only the plugins with no branch fragment.
r=$(mkrepo)
git -C "$r" commit -qm "feat: committed without a fragment" >/dev/null
out=$(write "$r" "feat(alpha): the pull request" --base main)
assert_eq "--base: fragment for the uncovered plugin" ".changes/alpha/feat-x-00000001.md" "$out"
git -C "$r" add -A >/dev/null && git -C "$r" commit -qm frag >/dev/null
out=$(write "$r" "feat(alpha): the pull request" --base main)
assert_eq "--base: a covered plugin is left alone" "" "$out"
assert_eq "--base: still one fragment" 1 "$(nfrag "$r")"

# 7. A subject the mapping cannot read needs --level.
r=$(mkrepo)
out=$(write "$r" "Add the widget")
assert_exit "non-Conventional subject: exit 2" 2 "$?"
assert_contains "names --level" "$out" "--level"
out=$(write "$r" "revert: undo the widget")
assert_exit "revert: exit 2" 2 "$?"
out=$(write "$r" "Add the widget" --level patch)
assert_contains "--level patch: bump" "$(frag "$r" "$out")" "bump: patch"
assert_contains "--level patch: Changed section, whole subject" "$(frag "$r" "$out")" $'### Changed\n\n- Add the widget'
r=$(mkrepo)
out=$(write "$r" "feat: x" --level none)
assert_contains "--level overrides the type" "$(frag "$r" "$out")" "bump: none"

# 8. Usage errors.
out=$(write "$r" "feat: x" --level huge)
assert_exit "bad --level: exit 2" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
