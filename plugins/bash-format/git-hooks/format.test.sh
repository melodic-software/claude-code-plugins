#!/usr/bin/env bash
# test-scope: plugins/bash-format/.claude-plugin/plugin.json
# Contract tests for the bash-format format entry (git-hooks/format.sh): staged
# shell scripts that an .editorconfig section governs are formatted and
# re-staged, a partly staged one is refused untouched, a script no section
# governs is never rewritten, an array-subscript rewrite shfmt would make is put
# back, --worktree does nothing, a merge leaves a script it takes unchanged
# from the merged branch alone, a missing tool follows the skip-key rule, the
# entry reports nothing and blocks on no lint finding, --resolve names the
# adapter or why none ran, and the plugin's own vendored installer wires both
# entries so `git commit` runs them and retires the earlier single entry.
# Expected values are the tools' documented output: a tab-indented body formats
# to the two spaces indent_size = 2 asks for (shfmt.1, EditorConfig); shfmt
# spaces the operator in an array subscript, [a-b] to [a - b]; SC2154 is
# "<var> is referenced but not assigned".
# test-scope: plugins/bash-format/git-hooks/entries.json plugins/bash-format/git-hooks/adapters.sh plugins/bash-format/git-hooks/shfmt-rewrite.sh
# test-scope: plugins/bash-format/lib/git-hooks/check-lib.sh plugins/bash-format/lib/git-hooks/install.mjs plugins/bash-format/lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016 # fixtures hold literal shell text, not expansions
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/format.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
for tool in git shfmt jq node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not on PATH -- format tests skipped"
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
  printf '# the repository opts in to ShellCheck\n' >"$REPO/.shellcheckrc"
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

new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a staged unformatted script is rewritten, listed on stdout, and exits 0" "0|a.sh|" "$(check "$REPO")"
expect "the rewrite is in the work tree" "$SPACED" "$(cat "$REPO/a.sh")"
expect "the rewrite is re-staged: the index holds the formatted bytes" "$SPACED" "$(git -C "$REPO" show :a.sh)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

new_repo
printf '%s\necho "$undefined_var"\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a lint finding does not block the format entry: it formats and exits 0" "0|a.sh|" "$(check "$REPO")"

new_repo
printf '%s\necho other\n' "$SHEBANG" >"$REPO/other.sh"
git -C "$REPO" add other.sh
git -C "$REPO" commit -q -m other --no-verify
printf '%s\necho other\necho unstaged\n' "$SHEBANG" >"$REPO/other.sh"
printf '%s\n' "$TABBED" >"$REPO/*.sh"
git -C "$REPO" add -- ':(literal)*.sh'
expect "a staged name holding glob characters re-stages only itself" "0|*.sh|" "$(check "$REPO")"
expect "glob name: an unstaged script it would match stays unstaged" "*.sh" "$(git -C "$REPO" diff --cached --name-only)"

new_repo
printf '%s\n' "$TABBED" >"$REPO/-lead.sh"
git -C "$REPO" add -- -lead.sh
expect "a name starting with - is formatted as a path" "0|-lead.sh|" "$(check "$REPO")"

new_repo
printf '%s\n' "$TABBED" >"$REPO/a.bash"
git -C "$REPO" add a.bash
expect "[*.sh] does not govern a .bash file, so it is not rewritten" "0||" "$(check "$REPO")"
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

# shfmt reads its config from the work tree; the commit holds the index's.
DRIFT='config differs between the index and the work tree; stage it or restore it, then commit'
new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
rm "$REPO/.editorconfig"
expect "an .editorconfig deleted from the work tree refuses the commit, naming it" "1||.editorconfig: $DRIFT" "$(check "$REPO")"
expect "the refused script is left as it was" "$TABBED" "$(cat "$REPO/a.sh")"

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
mkdir -p "$REPO/bin"
printf '%s\n' "$TABBED" >"$REPO/bin/gone.sh"
git -C "$REPO" add bin/gone.sh
rm -r "${REPO:?}/bin"
expect "staged then deleted from the work tree: nothing is rewritten" "0||" "$(check "$REPO")"
expect "staged then deleted: the script is not recreated" "no" "$([[ -e "$REPO/bin/gone.sh" ]] && echo yes || echo no)"
expect "staged then deleted: the index keeps its unformatted bytes" "$TABBED" "$(git -C "$REPO" show :bin/gone.sh)"

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
printf '%s\n' "$TABBED" >"$REPO/a.sh"
expect "--worktree: does nothing and passes" "0||" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$TABBED" "$(cat "$REPO/a.sh")"

# A merge being committed: a script the merged branch brings in unchanged is
# not rewritten; one the resolution edits is rewritten whole. main commits
# first so the merge cannot fast-forward.
merge_repo() {
  new_repo
  git -C "$REPO" checkout -q -b side
  printf '%s\nif true; then\n\tcd /tmp\nfi\n' "$SHEBANG" >"$REPO/x.sh"
  git -C "$REPO" add x.sh
  git -C "$REPO" commit -q -m side --no-verify
  git -C "$REPO" checkout -q main
  printf '%s\necho main\n' "$SHEBANG" >"$REPO/main.sh"
  git -C "$REPO" add main.sh
  git -C "$REPO" commit -q -m main --no-verify
  git -C "$REPO" merge -q --no-commit side >/dev/null 2>&1
}
merge_repo
expect "merge: the merge is in progress" yes "$([[ -f "$REPO/.git/MERGE_HEAD" ]] && echo yes)"
expect "merge: an inherited unformatted script is not rewritten" "0||" "$(check "$REPO")"
expect "merge: the inherited script's index entry is still side's" \
  "$(git -C "$REPO" show side:x.sh)" "$(git -C "$REPO" show :x.sh)"
merge_repo
printf 'cd /var\n' >>"$REPO/x.sh"
git -C "$REPO" add x.sh
expect "merge: a script the resolution edits is rewritten and listed" "0|x.sh|" "$(check "$REPO")"

# A PATH without one of the tools the script runs.
bin_without() { # <dir> <tool-to-omit>
  mkdir -p "$1"
  local t
  for t in git bash sh sed awk cat mktemp rm dirname grep tr head jq shfmt; do
    [[ "$t" == "$2" ]] || ln -s "$(command -v "$t")" "$1/$t"
  done
}
bin_without "$WORK/no-shfmt" shfmt
bin_without "$WORK/no-jq" jq

SF_INSTALL='see https://github.com/mvdan/sh#shfmt'
new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shfmt" bash "$CHECK" 2>&1)"
expect "missing shfmt where a section opts in: an agent fails with the install command" "1|FAIL: shfmt missing. Install: $SF_INSTALL
To skip only while shfmt is missing: git -c checks.skipmissing=shfmt commit ..." "$?|$out"
out="$(cd "$REPO" && PATH="$WORK/no-shfmt" bash "$CHECK" 2>&1)"
expect "missing shfmt: a person gets a notice and exit 0" "0|NOTICE: shfmt missing, so this check did not run. Install: $SF_INSTALL" "$?|$out"
git -C "$REPO" config checks.skipmissing shfmt
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shfmt" bash "$CHECK" 2>&1)"
expect "missing shfmt named in checks.skipmissing: the rewrite is skipped with a line" "0|SKIPPED: shfmt (missing)" "$?|$out"
printf '%s\necho unstaged\n' "$TABBED" >"$REPO/a.sh"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shfmt" bash "$CHECK" 2>&1)"
expect "missing shfmt skipped: a partly staged governed script is not refused" "0|SKIPPED: shfmt (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
printf '%s\n' "$TABBED" >"$REPO/a.sh"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-jq" bash "$CHECK" 2>&1)"
expect "missing jq where a section opts in: an agent fails, since the subscript guard needs it" \
  "1|FAIL: jq missing. Install: see https://jqlang.org/download/" "$?|${out%%$'\n'*}"

new_repo NONE
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shfmt" bash "$CHECK" 2>&1)"
expect "missing shfmt where no section opts in: nothing needs it" "0|" "$?|$out"

# --resolve: one row for the repository, or one per path; it runs nothing.
new_repo NONE
mkdir -p "$REPO/pkg" "$REPO/other"
printf '%s\n' "$EC" >"$REPO/pkg/.editorconfig"
printf '%s\n' "$TABBED" >"$REPO/pkg/a.sh"
printf '%s\n' "$TABBED" >"$REPO/other/b.sh"
git -C "$REPO" add pkg/.editorconfig
expect "--resolve finds a nested .editorconfig shell section" "bash-format	format	adapter:shfmt	shfmt	yes	config pkg/.editorconfig; binary shfmt on PATH" \
  "$(cd "$REPO" && bash "$CHECK" --resolve)"
expect "--resolve <path>: one row per file, the governing .editorconfig or none" "bash-format	format	adapter:shfmt	shfmt	yes	config pkg/.editorconfig; binary shfmt on PATH
bash-format	format	none		n/a	" "$(cd "$REPO" && bash "$CHECK" --resolve pkg/a.sh other/b.sh)"
expect "--resolve runs nothing: the files keep their bytes" "$TABBED|$TABBED" "$(cat "$REPO/pkg/a.sh")|$(cat "$REPO/other/b.sh")"
new_repo $'[*]\nend_of_line = lf'
mkdir -p "$REPO/.claude/ecosystems"
printf 'globs: ["*.sh"]\nfix-cmd: "stubfmt <files>"\n' >"$REPO/.claude/ecosystems/bash.yaml"
expect "--resolve with no shell section says so, and that hooks never run the bash record" "bash-format	format	none		n/a	no .editorconfig section names shell files; the bash record is not run by hooks; /toolchain:lint and /toolchain:check run it" \
  "$(cd "$REPO" && bash "$CHECK" --resolve)"
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh .claude
expect "a bash record with no adapter config runs nothing at commit" "0||" "$(check "$REPO")"
expect "the record's file stays as written" "$TABBED" "$(cat "$REPO/a.sh")"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs both entries" '[{"entry":"format","status":"installed"},{"entry":"lint","status":"installed"}]' "$status"
expect "the installed format copy carries the stamp on line 2" yes \
  "$(grep -qE '^# bash-format format sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/bash-format/format.sh") && echo yes)"
expect "the format entry's helpers are installed beside it" yes \
  "$([[ -f "$REPO/.git/hooks/bash-format/shfmt-rewrite.sh" && -f "$REPO/.git/hooks/bash-format/adapters.sh" && -f "$REPO/.git/hooks/bash-format/resolve-tool.sh" ]] && echo yes)"
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entries and succeeds" "0" "$?"
expect "the commit holds the formatted bytes" "$SPACED" "$(git -C "$REPO" show HEAD:a.sh)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf '%s\necho "$undefined_var"\n' "$SPACED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.sh:5: warning: undefined_var is referenced but not assigned. [SC2154]" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports both entries ok after the install" "ok	format
ok	lint" "$(node "$INSTALL" verify --repo "$REPO")"
printf '# edited\n' >>"$REPO/.git/hooks/bash-format/shfmt-rewrite.sh"
expect "verify reports a locally edited helper as modified" "modified	format" "$(node "$INSTALL" verify --repo "$REPO" | head -1 | cut -f1,2)"

# An install of the earlier single entry is reported for retirement, and a
# decline of it carries to both entries.
new_repo
mkdir -p "$REPO/.git/hooks/bash-format"
printf '#!/bin/sh\n# bash-format shell-check sha256:%064d\n' 0 >"$REPO/.git/hooks/bash-format/shell-check.sh"
expect "verify reports an earlier shell-check copy as superseded" yes \
  "$(grep -q '^superseded' <<<"$(node "$INSTALL" verify --repo "$REPO")" && echo yes)"
new_repo
git -C "$REPO" config checks.bash-format.shell-check.declined true
expect "a decline of shell-check carries to format and lint" "declined	format
declined	lint" "$(node "$INSTALL" verify --repo "$REPO" | cut -f1,2)"

echo "format: $PASS passed, $FAIL failed"
((FAIL == 0))
