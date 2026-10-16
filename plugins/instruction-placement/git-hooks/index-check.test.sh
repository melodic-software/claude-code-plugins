#!/usr/bin/env bash
# Contract tests for the instruction-placement pre-commit entry
# (git-hooks/index-check.sh): a commit that touches a rules file or the index
# file fails when the generated index is stale and prints the regenerate command,
# stays silent when the index is current, and does no work for any other commit;
# a repository with no index block is never failed; --worktree reports the same
# drift for uncommitted changes; and the plugin's own vendored installer wires
# the entry so `git commit` runs it from a flat installed copy.
# Expected values come from the requirement: a path-scoped rule the index block
# does not list is drift, and the block `render-index.sh write` produces is not.
# test-scope: plugins/instruction-placement/git-hooks/entries.json plugins/instruction-placement/scripts/render-index.sh plugins/instruction-placement/scripts/lib/discover.sh plugins/instruction-placement/lib/git-hooks/check-lib.sh plugins/instruction-placement/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/index-check.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
RENDER="$PLUGIN/scripts/render-index.sh"

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

BEGIN='<!-- BEGIN GENERATED: instruction-placement rules index -->'
END='<!-- END GENERATED: instruction-placement rules index -->'

n=0
# new_repo [noblock]: AGENTS.md carries an index block that says "no rules";
# the seed commit holds no rules file, so the index is current at the start.
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  mkdir -p "$REPO/src"
  printf 'class X {}\n' >"$REPO/src/a.cs"
  {
    printf '# Project\n\n'
    if [[ "${1:-}" != noblock ]]; then
      printf '%s\n\nNo path-scoped rules or nested instruction files are present in this repository.\n\n%s\n' "$BEGIN" "$END"
    fi
  } >"$REPO/AGENTS.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}

add_rule() { # <repo> [name]
  mkdir -p "$1/.claude/rules"
  printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# C# rule\n' >"$1/.claude/rules/${2:-csharp}.md"
}

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

rc_of() { printf '%s' "${1%%|*}"; }
err_of() { printf '%s' "${1##*|}"; }

new_repo
add_rule "$REPO"
git -C "$REPO" add .claude/rules/csharp.md
got="$(check "$REPO")"
expect "a staged rule the index does not list fails" 1 "$(rc_of "$got")"
expect "the failure names the index file and line" yes \
  "$(err_of "$got" | grep -qF 'AGENTS.md:1: the rules index no longer matches .claude/rules/.' && echo yes)"
expect "the failure carries the regenerate command for this repository" yes \
  "$(err_of "$got" | grep -qF "write --file \"$REPO/AGENTS.md\" --root \"$REPO\"" && echo yes)"

bash "$RENDER" write --file "$REPO/AGENTS.md" --root "$REPO" >/dev/null
git -C "$REPO" add AGENTS.md
expect "after the index is regenerated and staged the check passes silently" "0||" "$(check "$REPO")"

new_repo
add_rule "$REPO"
printf 'x\n' >"$REPO/src/b.cs"
git -C "$REPO" add src/b.cs
expect "a commit touching neither a rules file nor the index does no work, even with a stale index" "0||" "$(check "$REPO")"

new_repo
add_rule "$REPO"
git -C "$REPO" add .claude/rules/csharp.md
git -C "$REPO" commit -q -m rule --no-verify
printf 'more text\n' >>"$REPO/AGENTS.md"
git -C "$REPO" add AGENTS.md
expect "a staged edit to the index file runs the check and fails on drift" 1 "$(rc_of "$(check "$REPO")")"

new_repo
add_rule "$REPO"
bash "$RENDER" write --file "$REPO/AGENTS.md" --root "$REPO" >/dev/null
git -C "$REPO" add -A
git -C "$REPO" commit -q -m rule --no-verify
git -C "$REPO" rm -q .claude/rules/csharp.md
expect "a staged deletion of a rule the index lists fails" 1 "$(rc_of "$(check "$REPO")")"

new_repo noblock
add_rule "$REPO"
git -C "$REPO" add .claude/rules/csharp.md
expect "a repository with no index block is never failed" "0||" "$(check "$REPO")"

n=$((n + 1))
REPO="$WORK/r$n"
git init -q -b main "$REPO"
add_rule "$REPO"
git -C "$REPO" add .claude/rules/csharp.md
expect "a repository with no AGENTS.md or CLAUDE.md is never failed" "0||" "$(check "$REPO")"

new_repo
add_rule "$REPO"
expect "--worktree reports drift for an uncommitted, unstaged rule" 1 "$(rc_of "$(check "$REPO" --worktree)")"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"index-check","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(sed -n 2p "$REPO/.git/hooks/instruction-placement/index-check.sh" | grep -qE '^# instruction-placement index-check sha256:[0-9a-f]{64}$' && echo yes)"
expect "the renderer and its helper sit beside the installed copy" yes \
  "$([[ -f "$REPO/.git/hooks/instruction-placement/render-index.sh" && -f "$REPO/.git/hooks/instruction-placement/discover.sh" ]] && echo yes)"
add_rule "$REPO"
git -C "$REPO" add .claude/rules/csharp.md
err="$(git -C "$REPO" commit -q -m rule 2>&1)"
expect "git commit fails on a stale index" "1" "$?"
expect "the commit failure names the index file" "AGENTS.md:1:" "$(printf '%s\n' "$err" | head -1 | cut -c1-12)"
expect "the regenerate command in the failure points at the installed renderer" yes \
  "$(printf '%s\n' "$err" | grep -qF "bash \"$REPO/.git/hooks/instruction-placement/render-index.sh\" write" && echo yes)"
cmd="$(printf '%s\n' "$err" | sed -n 's/^.*Regenerate it: \(bash .*\), then stage.*$/\1/p' | head -1)"
(cd "$REPO" && eval "$cmd" >/dev/null 2>&1)
git -C "$REPO" add AGENTS.md
git -C "$REPO" commit -q -m rule >/dev/null 2>&1
expect "running the printed command and staging the index lets the commit through" "0" "$?"
expect "verify reports ok after the install" "ok	index-check" "$(node "$INSTALL" verify --repo "$REPO")"

echo "index-check: $PASS passed, $FAIL failed"
((FAIL == 0))
