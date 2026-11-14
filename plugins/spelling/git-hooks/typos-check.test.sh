#!/usr/bin/env bash
# spellchecker:off
# Contract tests for the spelling pre-commit entry (git-hooks/typos-check.sh):
# a typo on an added line blocks with "<path>:<line>: <message>", one on an
# unchanged line does not, a partly staged file is judged as staged, the
# repository's typos config (excludes, allow-list) governs, --worktree covers
# uncommitted and untracked files, a missing typos follows the skip-key rule,
# and the plugin's own vendored installer wires the entry so `git commit` runs it.
# The stub cases, which need no real typos, pin the path transport: paths reach
# typos on stdin (--file-list -), a path holding LF or CR goes alone on the
# command line, and a list typos cannot decode is retried there once.
# "teh" -> "the" is typos' own built-in correction, the fixture every case uses.
# test-scope: plugins/spelling/git-hooks/entries.json plugins/spelling/lib/git-hooks/check-lib.sh plugins/spelling/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/typos-check.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"

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
  err="$(cd "$repo" && bash "$CHECK" "$@" 2>&1 >/dev/null </dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$err"
}

# A stand-in typos, so the path transport is tested without a real typos. Each
# call appends its arguments (%q-quoted, one line per call) to $STUB_OUT/argv,
# and a --file-list - call copies stdin to $STUB_OUT/stdin and exits
# $STUB_RC_LIST (default 0). An ordinary path (no LF or CR) after -- exits 3,
# unless STUB_ALLOW_ARGV=1.
STUB="$WORK/stub"
export STUB_OUT="$WORK/stub-out"
mkdir -p "$STUB"
cat >"$STUB/typos" <<'EOF'
#!/usr/bin/env bash
printf ' %q' "$@" >>"$STUB_OUT/argv"
printf '\n' >>"$STUB_OUT/argv"
list=0 after=0 prev=
for a in "$@"; do
  if ((after)); then
    [[ "$a" == *$'\n'* || "$a" == *$'\r'* || "${STUB_ALLOW_ARGV:-}" == 1 ]] || exit 3
  elif [[ "$a" == -- ]]; then
    after=1
  elif [[ "$prev" == --file-list && "$a" == - ]]; then
    list=1
  fi
  prev="$a"
done
if ((list)); then
  cat >>"$STUB_OUT/stdin"
  exit "${STUB_RC_LIST:-0}"
fi
exit 0
EOF
chmod +x "$STUB/typos"

stub_check() { # <repo> [args...]: check with the stub typos first on PATH
  rm -rf "$STUB_OUT"
  mkdir -p "$STUB_OUT"
  : >"$STUB_OUT/argv"
  : >"$STUB_OUT/stdin"
  PATH="$STUB:$PATH" check "$@"
}

new_repo
mkdir -p "$REPO/sub"
printf 'clean a\n' >"$REPO/a.md"
printf 'clean b\n' >"$REPO/b.md"
printf 'clean c\n' >"$REPO/sub/c.md"
git -C "$REPO" add a.md b.md sub/c.md
printf 'loose\n' >"$REPO/untracked.md"
expect "stub: staged paths reach typos without a command-line path" "0|" "$(stub_check "$REPO")"
argv="$(cat "$STUB_OUT/argv")"
expect "stub: one typos call, ending in --file-list - with no --" yes \
  "$([[ "$argv" != *$'\n'* && "$argv" == *' --file-list -' && "$argv " != *' -- '* ]] && echo yes)"
expect "stub: the list on stdin is exactly the staged paths" "a.md
b.md
sub/c.md" "$(sort "$STUB_OUT/stdin")"
expect "stub: a typos status other than 0 or 2 from the list call blocks" \
  "1|spelling: typos exited 78 without a verdict; fix what it reports above." \
  "$(STUB_RC_LIST=78 stub_check "$REPO")"
expect "stub: a list typos cannot decode (74) is retried on the command line" "0|" \
  "$(STUB_RC_LIST=74 STUB_ALLOW_ARGV=1 stub_check "$REPO")"
expect "stub: the retry is one list call, then one command-line call" "2|yes" \
  "$(wc -l <"$STUB_OUT/argv" | tr -d ' ')|$([[ "$(sed -n 1p "$STUB_OUT/argv")" == *' --file-list -' && "$(sed -n 2p "$STUB_OUT/argv")" == *' -- a.md b.md sub/c.md' ]] && echo yes)"

for name in "l"$'\n'"f.md" "c"$'\r'"r.md"; do
  label="$(printf '%q' "$name")"
  new_repo
  if ! printf 'clean\n' >"$REPO/$name" 2>/dev/null; then
    echo "SKIP: the filesystem refuses the name $label"
    continue
  fi
  printf 'clean\n' >"$REPO/plain.md"
  git -C "$REPO" add -A
  expect "stub: $label passes" "0|" "$(stub_check "$REPO")"
  expect "stub: $label reaches typos alone after --, and plain.md on stdin" "$label|plain.md" \
    "$(line="$(grep -F -- ' -- ' "$STUB_OUT/argv")" && printf '%s' "${line##* -- }")|$(cat "$STUB_OUT/stdin")"
done

if ! command -v typos >/dev/null 2>&1; then
  echo "SKIP: typos not on PATH -- the real-typos cases skipped"
  echo "typos-check: $PASS passed, $FAIL failed"
  exit $((FAIL > 0))
fi

HINT='spelling: fix the words above, or allow-list intended ones in the repository typos config (extend-words).'

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
printf 'gone teh\n' >"$REPO/gone.md"
git -C "$REPO" add gone.md
rm "$REPO/gone.md"
expect "staged then deleted from the work tree: the staged typo still blocks" "1|gone.md:1: \`teh\` should be \`the\`
$HINT" "$(check "$REPO")"
printf '[files]\nextend-exclude = ["fixtures/"]\n' >"$REPO/_typos.toml"
mkdir -p "$REPO/fixtures"
printf 'fixture teh\n' >"$REPO/fixtures/gone.md"
git -C "$REPO" add _typos.toml fixtures/gone.md
git -C "$REPO" rm -q --cached gone.md
rm -r "$REPO/fixtures"
expect "staged then deleted: the repository config's excludes still hold" "0|" "$(check "$REPO")"
ln -s teh-target "$REPO/link.md"
git -C "$REPO" add link.md
rm "$REPO/link.md"
expect "staged then deleted: a staged symlink is not checked" "0|" "$(check "$REPO")"

new_repo
printf '[files]\nextend-exclude = ["fixtures/"]\n[default.extend-words]\nteh = "teh"\n' >"$REPO/_typos.toml"
mkdir -p "$REPO/fixtures"
printf 'fixture teh\n' >"$REPO/fixtures/a.md"
printf 'an old teh line\nallowed teh\n' >"$REPO/notes.md"
git -C "$REPO" add -A
expect "the repository typos config governs: an excluded path and an allow-listed word pass" "0|" "$(check "$REPO")"

new_repo
printf '[files]\nextend-exclude = ["fixtures/"]\n' >"$REPO/_typos.toml"
mkdir -p "$REPO/fixtures"
printf 'fixture teh\n' >"$REPO/fixtures/a.md"
printf 'clean line\n' >"$REPO/clean.md"
git -C "$REPO" add -A
expect "the repository typos config's exclude skips an explicitly staged whole file" "0|" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/sub"
printf '[default.extend-words]\nteh = "teh"\n' >"$REPO/sub/_typos.toml"
printf 'staged teh\n' >"$REPO/sub/a.md"
git -C "$REPO" add -A
printf 'staged teh\nunstaged\n' >"$REPO/sub/a.md"
expect "partly staged: a nested typos config's allow-list governs the staged copy" "0|" "$(check "$REPO")"
git -C "$REPO" add -A
rm "$REPO/sub/a.md"
expect "staged then deleted: a nested typos config's allow-list governs the staged copy" "0|" "$(check "$REPO")"

new_repo
printf '[default\n' >"$REPO/_typos.toml"
printf 'an old teh line\nclean line\n' >"$REPO/notes.md"
git -C "$REPO" add -A
got="$(check "$REPO")"
expect "a typos config typos cannot read blocks: no verdict is not a pass" "1|spelling: typos exited 78 without a verdict; fix what it reports above." \
  "${got%%|*}|$(printf '%s\n' "${got#*|}" | grep -F 'spelling:')"
printf 'an old teh line\nclean line\nstaged\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
printf 'an old teh line\nclean line\nstaged\nunstaged\n' >"$REPO/notes.md"
got="$(check "$REPO")"
expect "partly staged under a config typos cannot read: blocks too" "1|spelling: typos exited 78 without a verdict; fix what it reports above." \
  "${got%%|*}|$(printf '%s\n' "${got#*|}" | grep -F 'spelling:')"

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
  "$(grep -qE '^# spelling typos-check sha256:[0-9a-f]{64}$' <<<"$(sed -n 2p "$REPO/.git/hooks/spelling/typos-check.sh")" && echo yes)"
printf 'an old teh line\ncommitted teh\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
err="$(git -C "$REPO" commit -q -m change 2>&1)"
expect "git commit runs the entry and fails on the added line" "1" "$?"
expect "the commit failure names the line" "notes.md:2: \`teh\` should be \`the\`" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	typos-check" "$(node "$INSTALL" verify --repo "$REPO")"
expect "the bundled config is installed beside the copy" yes \
  "$(cmp -s "$PLUGIN/config/default-typos.toml" "$REPO/.git/hooks/spelling/default-typos.toml" && echo yes)"

# The bundled config ignores SHA-shaped hex (its extend-ignore-re): typos
# alone reads "1aded9f" as the misspelling "aded".
printf 'an old teh line\nfixed in 1aded9f\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "control: typos without the bundled config flags the SHA" 2 \
  "$(git -C "$REPO" show :notes.md | typos --format brief - >/dev/null 2>&1; echo $?)"
err="$(git -C "$REPO" commit -q -m sha 2>&1)"
expect "installed copy: the bundled config lets a SHA on an added line pass" "0|" "$?|$err"
printf 'an old teh line\nfixed in 1aded9f\nagain 1aded9f\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "plugin source: the script finds config/default-typos.toml too" "0|" "$(check "$REPO")"

# spellchecker:on
echo "typos-check: $PASS passed, $FAIL failed"
((FAIL == 0))
