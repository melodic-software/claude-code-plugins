#!/usr/bin/env bash
# spellchecker:off
# Contract tests for the spelling lint entry (git-hooks/lint.sh): the typos
# adapter runs with or without a repository typos config, a
# typo on an added line blocks with "<path>:<line>: <message>", one on an
# unchanged line does not, a partly staged file is judged as staged, the
# repository's typos config (excludes, allow-list) governs, typos failing with
# no finding fails closed, --worktree covers uncommitted and untracked files, a
# .claude/ecosystems/ record never runs, a missing typos follows the skip-key
# rule, and the plugin's own vendored installer wires the entry so `git commit`
# runs it. The stub cases, which need no real typos, pin the resolve rows and the path
# transport: paths reach typos as arguments after --.
# "teh" -> "the" is typos' own built-in correction, the fixture every case uses;
# typos --format brief prints "<path>:<line>:<col>: error: <message>" and exits
# 0 when clean, 2 on typos, anything else on an error
# (https://github.com/crate-ci/typos/blob/master/README.md).
# test-scope: plugins/spelling/git-hooks/entries.json plugins/spelling/git-hooks/adapters.sh
# test-scope: plugins/spelling/lib/git-hooks/check-lib.sh plugins/spelling/lib/git-hooks/resolve-tool.sh plugins/spelling/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/lint.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# HOME stays: a version-manager shim for typos (mise, asdf) reads its config
# from it. The --resolve rows below assume no ~/.claude/ecosystems/spelling.yaml.
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
new_repo() { # [NONE]: a repository with a root _typos.toml, or none
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  [[ "${1:-}" == NONE ]] || printf '[files]\n' >"$REPO/_typos.toml"
  printf 'an old teh line\n' >"$REPO/notes.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}

check() { # <repo> [args...] -> "<rc>|<stderr>"
  local repo="$1" err rc
  shift
  err="$(cd "$repo" && bash "$CHECK" "$@" 2>&1 >/dev/null </dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$err"
}

# A stand-in typos. Each call appends its arguments (%q-quoted, one line per
# call) to $STUB_OUT/argv; with STUB_RC set it prints a config error and exits
# that status, else it exits 0.
STUB="$WORK/stub"
export STUB_OUT="$WORK/stub-out"
mkdir -p "$STUB"
cat >"$STUB/typos" <<'EOF'
#!/usr/bin/env bash
printf ' %q' "$@" >>"$STUB_OUT/argv"
printf '\n' >>"$STUB_OUT/argv"
if [[ -n "${STUB_RC:-}" ]]; then
  echo 'typos: config error' >&2
  exit "$STUB_RC"
fi
exit 0
EOF
chmod +x "$STUB/typos"

stub_check() { # <repo> [args...]: check with the stub typos first on PATH
  rm -rf "$STUB_OUT"
  mkdir -p "$STUB_OUT"
  : >"$STUB_OUT/argv"
  PATH="$STUB:$PATH" check "$@"
}
after_dashdash() { # the paths of the first stub call
  local line
  line="$(sed -n 1p "$STUB_OUT/argv")"
  printf '%s' "${line##* -- }"
}

new_repo
mkdir -p "$REPO/sub"
printf 'clean a\n' >"$REPO/a.md"
printf 'clean b\n' >"$REPO/-b.md"
printf 'clean c\n' >"$REPO/sub/c.md"
git -C "$REPO" add -- a.md -b.md sub/c.md
printf 'loose\n' >"$REPO/untracked.md"
expect "stub: staged paths pass" "0|" "$(stub_check "$REPO")"
expect "stub: one typos call, the staged paths as arguments after --, a leading dash gaining ./" "1|./-b.md a.md sub/c.md" \
  "$(wc -l <"$STUB_OUT/argv" | tr -d ' ')|$(after_dashdash)"
expect "stub: the bundled config goes to typos with -c, findings in the brief format" yes \
  "$([[ "$(cat "$STUB_OUT/argv")" == *" -c $PLUGIN/config/default-typos.toml --force-exclude --format brief --color never -- "* ]] && echo yes)"
expect "stub: typos exiting non-zero with no finding fails closed, showing its output" \
  "1|spelling: typos exited 78 and reported no <path>:<line> finding, so the change was not checked:
typos: config error" "$(STUB_RC=78 stub_check "$REPO")"

name="l"$'\n'"f.md"
new_repo
if printf 'clean\n' >"$REPO/$name" 2>/dev/null; then
  git -C "$REPO" add -A
  expect "stub: a path holding LF reaches typos as one argument" "0|$(printf '%q' "$name")" \
    "$(stub_check "$REPO")$(after_dashdash)"
else
  echo "SKIP: the filesystem refuses a name holding LF"
fi

# No config gate: typos runs with or without a repository typos config, and
# --resolve names the config that governs, or says there is none.
new_repo NONE
printf 'an old teh line\nfresh teh line\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
stub_check "$REPO" >/dev/null
expect "no typos config: typos still runs on the staged files" "notes.md" "$(after_dashdash)"
NONE_DETAIL='no typos config: typos defaults plus the bundled config; binary typos on PATH'
expect "no typos config: --resolve resolves the adapter and says no config governs" "spelling	lint	adapter:typos	typos	yes	$NONE_DETAIL" \
  "$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" --resolve)"
printf '[project]\nname = "x"\n' >"$REPO/pyproject.toml"
git -C "$REPO" add pyproject.toml
expect "a pyproject.toml with no [tool.typos] section is not named as the config" "spelling	lint	adapter:typos	typos	yes	$NONE_DETAIL" \
  "$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" --resolve)"
printf '[project]\nname = "x"\n\n[tool.typos.default.extend-words]\nfoo = "foo"\n' >"$REPO/pyproject.toml"
git -C "$REPO" add pyproject.toml
expect "--resolve names a pyproject.toml [tool.typos] section" "spelling	lint	adapter:typos	typos	yes	config pyproject.toml; binary typos on PATH" \
  "$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" --resolve)"

new_repo NONE
printf '[package]\nname = "x"\n\n[package.metadata.typos]\n' >"$REPO/Cargo.toml"
git -C "$REPO" add -A
expect "--resolve names a Cargo.toml [package.metadata.typos] section" "spelling	lint	adapter:typos	typos	yes	config Cargo.toml; binary typos on PATH" \
  "$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" --resolve)"

new_repo NONE
mkdir -p "$REPO/docs" "$REPO/src"
printf '[files]\n' >"$REPO/docs/typos.toml"
printf 'clean\n' >"$REPO/docs/a.md"
printf 'clean\n' >"$REPO/src/b.md"
git -C "$REPO" add -A
stub_check "$REPO" >/dev/null
expect "a nested typos config does not narrow what runs" "docs/a.md docs/typos.toml src/b.md" "$(after_dashdash)"
expect "--resolve per path names the governing config, or none" "spelling	lint	adapter:typos	typos	yes	config docs/typos.toml; binary typos on PATH
spelling	lint	adapter:typos	typos	yes	$NONE_DETAIL" "$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" --resolve docs/a.md src/b.md)"
expect "--resolve finds a nested config for the repository row" "spelling	lint	adapter:typos	typos	yes	config docs/typos.toml; binary typos on PATH" \
  "$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" --resolve)"

# A record never runs from the entry.
BIN="$WORK/bin"
mkdir -p "$BIN"
printf '#!/bin/sh\ntouch "%s/stublint-ran"\nexit 1\n' "$WORK" >"$BIN/stublint"
chmod +x "$BIN/stublint"
for cfg in yes NONE; do
  if [[ "$cfg" == NONE ]]; then new_repo NONE; else new_repo; fi
  mkdir -p "$REPO/.claude/ecosystems"
  printf 'globs: ["**"]\nlint-cmd: "stublint <files>"\n' >"$REPO/.claude/ecosystems/spelling.yaml"
  printf 'clean\n' >"$REPO/a.md"
  git -C "$REPO" add -A
  rm -f "$WORK/stublint-ran"
  PATH="$BIN:$PATH" stub_check "$REPO" >/dev/null
  expect "a spelling record's lint-cmd never runs (typos config: $cfg)" no "$([[ -e "$WORK/stublint-ran" ]] && echo yes || echo no)"
done
expect "--resolve says the record is not run by hooks" "spelling	lint	adapter:typos	typos	yes	$NONE_DETAIL; the spelling record is not run by hooks; /toolchain:lint and /toolchain:check run it" \
  "$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" --resolve)"

if ! command -v typos >/dev/null 2>&1; then
  echo "SKIP: typos not on PATH -- the real-typos cases skipped"
  echo "lint: $PASS passed, $FAIL failed"
  exit $((FAIL > 0))
fi

HINT='spelling: fix the words above, or allow-list intended ones in the repository typos config (extend-words).'

new_repo
printf 'an old teh line\nfresh teh line\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "an added line with a typo blocks, naming that line only" "1|notes.md:2: \`teh\` should be \`the\`
$HINT" "$(check "$REPO")"
expect "lint rewrites nothing" "$(printf 'an old teh line\nfresh teh line')" "$(cat "$REPO/notes.md")"

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
expect "a typos config typos cannot read blocks: no verdict is not a pass" "1|spelling: typos exited 78 and reported no <path>:<line> finding, so the change was not checked:" \
  "${got%%|*}|$(printf '%s\n' "${got#*|}" | grep -F 'spelling:' | sort -u)"
printf 'an old teh line\nclean line\nstaged\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
printf 'an old teh line\nclean line\nstaged\nunstaged\n' >"$REPO/notes.md"
got="$(check "$REPO")"
expect "partly staged under a config typos cannot read: blocks too" "1|spelling: typos exited 78 and reported no <path>:<line> finding, so the change was not checked:" \
  "${got%%|*}|$(printf '%s\n' "${got#*|}" | grep -F 'spelling:' | sort -u)"

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

new_repo NONE
printf 'an old teh line\nfresh teh line\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "real typos, no typos config: the typo on an added line still blocks" "1|notes.md:2: \`teh\` should be \`the\`
$HINT" "$(check "$REPO")"

# A PATH with git and the shell tools the script runs, but no typos.
NOTYPOS="$WORK/notypos"
mkdir -p "$NOTYPOS"
for t in git bash sh sed awk cat mktemp rm dirname grep tr; do
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
new_repo NONE
printf 'an old teh line\nfresh teh\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOTYPOS" bash "$CHECK" 2>&1)"
expect "missing typos with no typos config: an agent still fails" "1|FAIL: typos missing." "$?|$(printf '%s\n' "$out" | head -1 | cut -c1-20)"

# End to end through the plugin's vendored installer and a real commit.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"lint","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# spelling lint sha256:[0-9a-f]{64}$' <<<"$(sed -n 2p "$REPO/.git/hooks/spelling/lint.sh")" && echo yes)"
printf 'an old teh line\ncommitted teh\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
err="$(git -C "$REPO" commit -q -m change 2>&1)"
expect "git commit runs the entry and fails on the added line" "1" "$?"
expect "the commit failure names the line" "notes.md:2: \`teh\` should be \`the\`" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	lint" "$(node "$INSTALL" verify --repo "$REPO")"
expect "the bundled config, resolver and adapter are installed beside the copy" yes \
  "$(cmp -s "$PLUGIN/config/default-typos.toml" "$REPO/.git/hooks/spelling/default-typos.toml" &&
    cmp -s "$PLUGIN/lib/git-hooks/resolve-tool.sh" "$REPO/.git/hooks/spelling/resolve-tool.sh" &&
    cmp -s "$PLUGIN/git-hooks/adapters.sh" "$REPO/.git/hooks/spelling/adapters.sh" && echo yes)"

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

# An install made under the old entry name is superseded drift, and a decline
# of the old entry carries over.
new_repo
mkdir -p "$REPO/.git/hooks/spelling"
git -C "$REPO" config --local checks.spelling.typos-check.declined true
expect "a decline of the retired typos-check entry carries to lint" "declined	lint" \
  "$(node "$INSTALL" verify --repo "$REPO" | cut -f1,2)"

# spellchecker:on
echo "lint: $PASS passed, $FAIL failed"
((FAIL == 0))
