#!/usr/bin/env bash
# Contract tests for the typos-format pre-commit entry (git-hooks/typos-check.sh):
# a typo on an added line blocks with "<path>:<line>: <message>", one on an
# unchanged line does not, a partly staged file is judged as staged, the
# repository's typos config (excludes, allow-list) governs, --worktree covers
# uncommitted and untracked files, a missing typos follows the skip-key rule,
# and the plugin's own vendored installer wires the entry so `git commit` runs it.
# "teh" -> "the" is typos' own built-in correction, the fixture every case uses.
# test-scope: plugins/typos-format/git-hooks/entries.json plugins/typos-format/lib/git-hooks/check-lib.sh plugins/typos-format/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/typos-check.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v typos >/dev/null 2>&1; then
  echo "SKIP: typos not on PATH -- typos-check tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  printf 'an old teh line\n' >"$REPO/notes.md"
  git -C "$REPO" add notes.md
  git -C "$REPO" commit -q -m seed --no-verify
}

check() { # <repo> [args...] -> "<rc>|<stderr>"
  local repo="$1" err rc
  shift
  err="$(cd "$repo" && bash "$CHECK" "$@" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$err"
}

HINT='typos-format: fix the words above, or allow-list intended ones in the repository typos config (extend-words).'

new_repo
printf 'an old teh line\nfresh teh line\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "an added line with a typo blocks, naming that line only" "1|notes.md:2: \`teh\` should be \`the\`
$HINT" "$(check "$REPO")"

new_repo
printf 'an old teh line\nclean line\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "a typo on an unchanged line does not block" "0|" "$(check "$REPO")"

new_repo
printf 'an old teh line\nstaged teh\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
printf 'an old teh line\nstaged the\n' >"$REPO/notes.md"
expect "partly staged: the staged typo blocks though the work tree is fixed" "1|notes.md:2: \`teh\` should be \`the\`
$HINT" "$(check "$REPO")"
printf 'an old teh line\nstaged ok\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
printf 'an old teh line\nstaged ok\nunstaged teh\n' >"$REPO/notes.md"
expect "partly staged: an unstaged typo does not block the commit" "0|" "$(check "$REPO")"

new_repo
printf '[files]\nextend-exclude = ["fixtures/"]\n[default.extend-words]\nteh = "teh"\n' >"$REPO/_typos.toml"
mkdir -p "$REPO/fixtures"
printf 'fixture teh\n' >"$REPO/fixtures/a.md"
printf 'an old teh line\nallowed teh\n' >"$REPO/notes.md"
git -C "$REPO" add -A
expect "the repository typos config governs: an excluded path and an allow-listed word pass" "0|" "$(check "$REPO")"

new_repo
printf 'an old teh line\nuncommitted teh\n' >"$REPO/notes.md"
expect "--worktree: an uncommitted typo blocks" "1|notes.md:2: \`teh\` should be \`the\`
$HINT" "$(check "$REPO" --worktree)"
git -C "$REPO" checkout -q notes.md
printf 'loose teh\n' >"$REPO/new.md"
expect "--worktree: an untracked file is checked whole" "1|new.md:1: \`teh\` should be \`the\`
$HINT" "$(check "$REPO" --worktree)"
rm "$REPO/new.md"
expect "--worktree: no uncommitted change passes" "0|" "$(check "$REPO" --worktree)"

# A PATH with git and the shell tools the script runs, but no typos.
NOTYPOS="$WORK/notypos"
mkdir -p "$NOTYPOS"
for t in git bash sed awk cat mktemp rm dirname grep tr; do
  ln -s "$(command -v "$t")" "$NOTYPOS/$t"
done
new_repo
printf 'an old teh line\nfresh teh\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOTYPOS" bash "$CHECK" 2>&1)"
expect "missing typos: an agent fails with the install command" "1" "$?"
expect "missing typos: the message names the tool and the skip key" \
  "FAIL: typos missing. Install: cargo install typos-cli, or another method at https://github.com/crate-ci/typos#install
To skip only while typos is missing: git -c checks.skipmissing=typos commit ..." "$out"
git -C "$REPO" config checks.skipmissing typos
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOTYPOS" bash "$CHECK" 2>&1)"
expect "missing typos named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: typos (missing)" "$?|$out"

# End to end through the plugin's vendored installer and a real commit.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"typos-check","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# typos-format typos-check sha256:[0-9a-f]{64}$' <<<"$(sed -n 2p "$REPO/.git/hooks/typos-format/typos-check.sh")" && echo yes)"
printf 'an old teh line\ncommitted teh\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
err="$(git -C "$REPO" commit -q -m change 2>&1)"
expect "git commit runs the entry and fails on the added line" "1" "$?"
expect "the commit failure names the line" "notes.md:2: \`teh\` should be \`the\`" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	typos-check" "$(node "$INSTALL" verify --repo "$REPO")"
expect "the bundled config is installed beside the copy" yes \
  "$(cmp -s "$PLUGIN/config/default-typos.toml" "$REPO/.git/hooks/typos-format/default-typos.toml" && echo yes)"

# The bundled config ignores SHA-shaped hex, as the per-edit hook does: typos
# alone reads "1aded9f" as the misspelling "aded".
printf 'an old teh line\nfixed in 1aded9f\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "control: typos without the bundled config flags the SHA" 2 \
  "$(git -C "$REPO" show :notes.md | typos --format brief - >/dev/null 2>&1; echo $?)"
err="$(git -C "$REPO" commit -q -m sha 2>&1)"
expect "installed copy: a SHA on an added line passes, as with the per-edit hook" "0|" "$?|$err"
printf 'an old teh line\nfixed in 1aded9f\nagain 1aded9f\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "plugin source: the script finds config/default-typos.toml too" "0|" "$(check "$REPO")"

echo "typos-check: $PASS passed, $FAIL failed"
((FAIL == 0))
