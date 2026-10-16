#!/usr/bin/env bash
# Contract tests for the bash-format pre-commit entry (git-hooks/shell-check.sh):
# staged shell scripts that an .editorconfig section governs are formatted and
# re-staged, a partly staged one is refused untouched, a ShellCheck finding blocks
# only on a line the commit adds, a script no section governs is never rewritten
# but is still checked, an array-subscript rewrite shfmt would make is put back,
# --worktree reports without rewriting, a missing tool follows the skip-key rule,
# and the plugin's own vendored installer wires the entry so `git commit` runs it.
# Expected values are the tools' documented output: a tab-indented body formats to
# the two spaces indent_size = 2 asks for; SC2154 is "<var> is referenced but not
# assigned"; shfmt spaces the operator in the subscript [a-b] (mvdan/sh issue 956).
# test-scope: plugins/bash-format/git-hooks/entries.json plugins/bash-format/lib/git-hooks/check-lib.sh plugins/bash-format/lib/git-hooks/install.mjs
# shellcheck disable=SC2016 # fixtures hold literal shell text, not expansions
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/shell-check.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
for tool in shfmt shellcheck jq git node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not on PATH -- shell-check tests skipped"
    exit 0
  fi
done

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

EC=$'[*.sh]\nindent_style = space\nindent_size = 2'
n=0
new_repo() { # [.editorconfig body; "NONE" for no .editorconfig]
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  if [[ "${1:-}" != NONE ]]; then
    printf '%s\n' "${1:-$EC}" >"$REPO/.editorconfig"
  fi
  printf '#!/usr/bin/env bash\necho seed\n' >"$REPO/seed.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

SHEBANG='#!/usr/bin/env bash'
TABBED="$SHEBANG"$'\nif true; then\n\techo hi\nfi'
SPACED="$SHEBANG"$'\nif true; then\n  echo hi\nfi'
HINT='bash-format: fix the findings above, or adjust the repository .shellcheckrc.'

new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a staged unformatted script is rewritten, listed on stdout, and exits 0" "0|a.sh|" "$(check "$REPO")"
expect "the rewrite is in the work tree" "$SPACED" "$(cat "$REPO/a.sh")"
expect "the rewrite is re-staged: the index holds the formatted bytes" "$SPACED" "$(git -C "$REPO" show :a.sh)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

new_repo
printf '%s\n' "$TABBED" >"$REPO/a.bash"
git -C "$REPO" add a.bash
expect "a .bash file is checked but [*.sh] does not govern it, so it is not rewritten" "0||" "$(check "$REPO")"
new_repo $'[*.{sh,bash}]\nindent_style = space\nindent_size = 2'
printf '%s\n' "$TABBED" >"$REPO/a.bash"
git -C "$REPO" add a.bash
expect "a .bash file is rewritten when a brace list governs it" "0|a.bash|" "$(check "$REPO")"

new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
printf '%s\necho more\n' "$TABBED" >"$REPO/a.sh"
expect "a partly staged governed script is refused with the contract line" "1||a.sh: partly staged; format it or stage it fully, then commit" "$(check "$REPO")"
expect "a refused script is left byte for byte" "$TABBED"$'\necho more' "$(cat "$REPO/a.sh")"
expect "a refused script's index entry is left byte for byte" "$TABBED" "$(git -C "$REPO" show :a.sh)"

new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
printf 'notes\n' >"$REPO/notes.md"
git -C "$REPO" add a.sh notes.md
printf 'notes\nmore unstaged\n' >"$REPO/notes.md"
expect "a partly staged file that is not shell does not refuse the commit" "0|a.sh|" "$(check "$REPO")"

new_repo NONE
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
printf '%s\necho more\n' "$TABBED" >"$REPO/a.sh"
expect "a partly staged script no section governs is not refused" "0||" "$(check "$REPO")"

new_repo
printf '%s\necho "$undefined_var"\n' "$SPACED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a finding on an added line blocks, naming that line" "1||a.sh:5: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO")"

new_repo
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
git -C "$REPO" commit -q -m old --no-verify
printf '%s\necho "$undefined_var"\necho ok\n' "$SHEBANG" >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

new_repo
printf '%s\nunused_variable=1\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a warning-level finding (SC2034) blocks" "1||a.sh:2: warning: unused_variable appears unused. Verify use (or export if used externally). [SC2034]
$HINT" "$(check "$REPO")"

new_repo
printf '%s\necho $1\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "an info-level finding (SC2086) does not block" "0||" "$(check "$REPO")"

new_repo NONE
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "no .editorconfig: the script is not touched and the check passes" "0||" "$(check "$REPO")"
expect "no .editorconfig: bytes are as written" "$TABBED" "$(cat "$REPO/a.sh")"

new_repo $'[*]\nend_of_line = lf\nindent_style = space'
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a bare [*] section does not opt in" "0||" "$(check "$REPO")"
expect "a bare [*] section: bytes are as written" "$TABBED" "$(cat "$REPO/a.sh")"

new_repo NONE
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "no .editorconfig: ShellCheck still reports" "1||a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO")"

new_repo $'root = true\n\n[*.sh]\nindent_style = space\nindent_size = 2'
mkdir -p "$REPO/pkg/sub"
printf 'root = true\n\n[*.md]\nindent_size = 4\n' >"$REPO/pkg/.editorconfig"
printf '%s\n' "$TABBED" >"$REPO/pkg/sub/b.sh"
git -C "$REPO" add pkg/sub/b.sh
expect "a nested root = true config with no shell section ends the walk" "0||" "$(check "$REPO")"

new_repo $'[*.sh]\nindent_style = space\nindent_size = 2\n\n[gen/*.sh]\nignore = true'
mkdir -p "$REPO/gen"
printf '%s\n' "$TABBED" >"$REPO/gen/g.sh"
git -C "$REPO" add gen/g.sh
expect "a file an ignore = true section covers is left alone" "0||" "$(check "$REPO")"
expect "an ignored file keeps its bytes" "$TABBED" "$(cat "$REPO/gen/g.sh")"

new_repo
printf '%s\ndeclare -A m\nm[a-b]=1\necho "${m[a-b]}"\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
out="$(check "$REPO")"
expect "an array-subscript rewrite is put back: the commit check passes, nothing listed" "0|" "${out%|*}"
expect "the subscript rewrite leaves the bytes as written" "$SHEBANG"$'\ndeclare -A m\nm[a-b]=1\necho "${m[a-b]}"' "$(cat "$REPO/a.sh")"
expect "the subscript guard says why on stderr" "bash-format: shfmt would rewrite the array subscripts \`[a-b]\` on line 3 as \`[a - b]\`, \`[a-b]\` on line 4 as \`[a - b]\`, each a different key if the array is associative, so a.sh was left as written. Quote the key ([\"a-b\"]) if the array is associative; if it is indexed, write it as shfmt prints it ([a - b])." "${out##*|}"

# An unclassified shfmt probe failure leaves the file alone and says so; only a
# confirmed unsupported-flag rejection may fall back to a plain format.
mkdir -p "$WORK/flake"
cat >"$WORK/flake/shfmt" <<'STUB'
#!/usr/bin/env bash
echo "shfmt-wrapper: transient startup failure" >&2
exit 1
STUB
chmod +x "$WORK/flake/shfmt"
new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
out="$(cd "$REPO" && PATH="$WORK/flake:$PATH" bash "$CHECK" 2>&1)"
expect "an unclassified probe failure: exit 0, the file untouched, the skip said out loud" "0|bash-format: shfmt probe failed (shfmt-wrapper: transient startup failure); a.sh not formatted.|$TABBED" "$?|$out|$(cat "$REPO/a.sh")"

new_repo
mkdir -p "$REPO/.githooks/bash-format"
printf '%s\n' "$TABBED" >"$REPO/.githooks/bash-format/copy.sh"
git -C "$REPO" add -f .githooks/bash-format/copy.sh
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"

new_repo
printf '%s\necho "$undefined_var"\n' "$TABBED" >"$REPO/a.sh"
expect "--worktree: an uncommitted finding blocks and nothing is rewritten" "1||a.sh:5: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$TABBED"$'\necho "$undefined_var"' "$(cat "$REPO/a.sh")"
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/a.sh"
expect "--worktree: an untracked file is checked whole" "1||a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO" --worktree)"
rm "$REPO/a.sh"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

# A PATH without one of the tools the script runs.
bin_without() { # <dir> <tool-to-omit>
  mkdir -p "$1"
  local t
  for t in git bash sed awk cat mktemp rm dirname grep tr jq shfmt shellcheck; do
    [[ "$t" == "$2" ]] || ln -s "$(command -v "$t")" "$1/$t"
  done
}
bin_without "$WORK/no-shellcheck" shellcheck
bin_without "$WORK/no-shfmt" shfmt

SC_INSTALL='see https://github.com/koalaman/shellcheck#installing'
SF_INSTALL='see https://github.com/mvdan/sh#shfmt'
new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shellcheck" bash "$CHECK" 2>&1)"
expect "missing shellcheck: an agent fails with the install command" "1" "$?"
expect "missing shellcheck: the message names the tool and the skip key" \
  "a.sh
FAIL: shellcheck missing. Install: $SC_INSTALL
To skip only while shellcheck is missing: git -c checks.skipmissing=shellcheck commit ..." "$out"
out="$(cd "$REPO" && PATH="$WORK/no-shellcheck" bash "$CHECK" 2>&1)"
expect "missing shellcheck: a person gets a notice and exit 0" "0|NOTICE: shellcheck missing, so this check did not run. Install: $SC_INSTALL" "$?|$out"
git -C "$REPO" config checks.skipmissing shellcheck
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shellcheck" bash "$CHECK" 2>&1)"
expect "missing shellcheck named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: shellcheck (missing)" "$?|$out"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shellcheck" bash "$CHECK" --worktree 2>&1)"
git -C "$REPO" config --unset checks.skipmissing
expect "missing shellcheck, --worktree: silent" "0|" "$?|$out"

new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shfmt" bash "$CHECK" 2>&1)"
expect "missing shfmt where a section opts in: an agent fails with the install command" "1|FAIL: shfmt missing. Install: $SF_INSTALL
To skip only while shfmt is missing: git -c checks.skipmissing=shfmt commit ..." "$?|$out"
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
git -C "$REPO" config checks.skipmissing shfmt
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shfmt" bash "$CHECK" 2>&1)"
expect "missing shfmt named in checks.skipmissing: the rewrite is skipped and ShellCheck still reports" "1|SKIPPED: shfmt (missing)
a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing

new_repo NONE
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shfmt" bash "$CHECK" 2>&1)"
expect "missing shfmt where no section opts in: nothing needs it" "0|" "$?|$out"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"shell-check","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# bash-format shell-check sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/bash-format/shell-check.sh") && echo yes)"
expect "the shared rewrite helper is installed beside the script" yes \
  "$([[ -f "$REPO/.git/hooks/bash-format/shfmt-rewrite.sh" ]] && echo yes)"
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entry and succeeds" "0" "$?"
expect "the commit holds the formatted bytes" "$SPACED" "$(git -C "$REPO" show HEAD:a.sh)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf '%s\necho "$undefined_var"\n' "$SPACED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.sh:5: warning: undefined_var is referenced but not assigned. [SC2154]" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	shell-check" "$(node "$INSTALL" verify --repo "$REPO")"
printf '# edited\n' >>"$REPO/.git/hooks/bash-format/shfmt-rewrite.sh"
expect "verify reports a locally edited helper as modified" "modified	shell-check" "$(node "$INSTALL" verify --repo "$REPO" | cut -f1,2)"

echo "shell-check: $PASS passed, $FAIL failed"
((FAIL == 0))
