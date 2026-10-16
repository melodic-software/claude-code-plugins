#!/usr/bin/env bash
# Contract tests for the guardrails pre-push entry git-hooks/reference-verify.sh:
# an unknown CLI flag or a cited path the repository deleted, on a line the
# pushed commits add, blocks with "<path>:<line>: <message>"; the same text on an
# unchanged line, or in a file type the verifiers do not read, does not; a new
# branch ranges from its merge-base with the remote's default branch and a
# deletion checks nothing; the failure names the way out (decline the entry;
# the skip key covers only a missing jq); --worktree covers uncommitted files;
# and the plugin's vendored installer wires the entry as a pre-push hook, so
# `git commit` does not run it and `git push` does.
# test-scope: plugins/guardrails/git-hooks/entries.json plugins/guardrails/hooks/run-guards.sh plugins/guardrails/hooks/cli-flag-verify.sh plugins/guardrails/hooks/stale-path-verify.sh plugins/guardrails/hooks/skill-reference-verify.sh plugins/guardrails/lib/git-hooks/install.mjs plugins/guardrails/lib/git-hooks/check-lib.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/reference-verify.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH -- reference-verify tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

# A fake CLI whose --help lists one real flag, the only binary the flag
# verifier scans here, with a per-run cache.
mkdir -p "$WORK/bin" "$WORK/cache"
# shellcheck disable=SC2016 # the fake tool's script text: its $ expands when it runs, not here
printf '#!/usr/bin/env bash\nfor a in "$@"; do last="$a"; done\n[[ "$last" == --help ]] && echo "  --real  a real flag"\nexit 0\n' \
  >"$WORK/bin/faketool"
chmod +x "$WORK/bin/faketool"
export PATH="$WORK/bin:$PATH" CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool
export XDG_CACHE_HOME="$WORK/cache" LOCALAPPDATA="$WORK/cache"

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

ZERO=0000000000000000000000000000000000000000
n=0
# new_repo: a repository whose main is pushed to a bare origin, with
# origin/HEAD set, and whose history deleted docs/gone.md.
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q --bare -b main "$WORK/r$n.git"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  printf '#!/usr/bin/env bash\nfaketool --real\n' >"$REPO/run.sh"
  mkdir -p "$REPO/docs"
  printf 'gone\n' >"$REPO/docs/gone.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
  git -C "$REPO" rm -q docs/gone.md
  git -C "$REPO" commit -q -m "remove docs/gone.md" --no-verify
  git -C "$REPO" remote add origin "$WORK/r$n.git"
  git -C "$REPO" push -q --no-verify origin main 2>/dev/null
  git -C "$REPO" remote set-head origin main >/dev/null
  BASE="$(git -C "$REPO" rev-parse HEAD)"
}

commit_all() { # <message>
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "$1" --no-verify
}

# push_check <ref> <local-sha> <remote-sha> -> "<rc>|<first stderr line>", the
# way git runs a pre-push hook: remote name and url as args, refs on stdin.
push_check() {
  local err rc
  err="$(cd "$REPO" && printf '%s %s %s %s\n' "$1" "$2" "$1" "$3" |
    bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(head -1 <<<"$err")"
}

push_err() { # <ref> <local-sha> <remote-sha> -> the whole stderr
  local err
  err="$(cd "$REPO" && printf '%s %s %s %s\n' "$1" "$2" "$1" "$3" |
    bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  printf '%s\n' "$err"
}

worktree_check() { # -> "<rc>|<first stderr line>"
  local err rc
  err="$(cd "$REPO" && bash "$CHECK" --worktree 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(head -1 <<<"$err")"
}

FLAG_FINDING="cli-flag-verify: unknown flag(s) in run.sh, unverified, not proven wrong: the installed --help may predate the flag."

new_repo
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all bogus
expect "an unknown flag on a line the push adds blocks, at that line" "1|run.sh:3: $FLAG_FINDING" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"

err="$(push_err refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"
expect "the failure names the decline route for this entry" yes \
  "$(grep -qF 'install.mjs decline --entry reference-verify' <<<"$err" && grep -qF '/guardrails:setup' <<<"$err" && echo yes)"
expect "the failure says the skip key covers only a missing jq" yes \
  "$(grep -qF 'checks.skipmissing=jq' <<<"$err" && grep -qi 'only while jq is missing' <<<"$err" && echo yes)"

new_repo
printf '#!/usr/bin/env bash\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all old
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nfaketool --bogus\necho fine\n' >"$REPO/run.sh"
commit_all more
expect "an unknown flag on a line an earlier push added does not block" "0|" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"

new_repo
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf 'See `docs/gone.md` for the details.\n' >"$REPO/README.md"
commit_all readme
expect "a new file citing a deleted repository path blocks" \
  "1|README.md:1: stale-path-verify: cited path(s) in README.md were deleted from this repo:" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"

# The verifiers judge the pushed tip's tree, not the checkout. Each case below
# pushes a branch while main, which differs from it, is checked out.
# new_readme_repo: new_repo plus a pushed README.md, so a branch edits it.
new_readme_repo() {
  new_repo
  printf '# R\n' >"$REPO/README.md"
  commit_all readme
  git -C "$REPO" push -q --no-verify origin main 2>/dev/null
}

# A branch that restores a deleted path may cite it.
new_readme_repo
git -C "$REPO" checkout -q -b restore
mkdir -p "$REPO/docs"
printf 'gone\n' >"$REPO/docs/gone.md"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf '# R\nSee `docs/gone.md` for the details.\n' >"$REPO/README.md"
commit_all restore
tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q main
expect "a pushed tip that holds a cited path passes though the checkout lacks it" "0|" \
  "$(push_check refs/heads/restore "$tip" "$ZERO")"
expect "the check leaves no worktree behind" 1 "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')"

# A branch that deletes a cited path blocks though the checkout has the file.
new_readme_repo
mkdir -p "$REPO/docs"
printf 'kept\n' >"$REPO/docs/kept.md"
commit_all kept
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
git -C "$REPO" checkout -q -b drop
git -C "$REPO" rm -q docs/kept.md
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf '# R\nSee `docs/kept.md` for the details.\n' >"$REPO/README.md"
commit_all drop
tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q main
expect "a pushed tip that deletes a cited path blocks though the checkout has it" \
  "1|README.md:2: stale-path-verify: cited path(s) in README.md were deleted from this repo:" \
  "$(push_check refs/heads/drop "$tip" "$ZERO")"

# A file only the pushed branch has is still judged.
new_repo
git -C "$REPO" checkout -q -b fresh
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf 'See `docs/gone.md` for the details.\n' >"$REPO/NEW.md"
commit_all fresh
tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q main
expect "a file the checkout lacks is judged from the pushed tip" \
  "1|NEW.md:1: stale-path-verify: cited path(s) in NEW.md were deleted from this repo:" \
  "$(push_check refs/heads/fresh "$tip" "$ZERO")"

# A force-added gitignored file is what the push sends, so it is verified.
new_repo
printf 'tool.sh\n' >"$REPO/.gitignore"
printf '#!/usr/bin/env bash\nfaketool --bogus\n' >"$REPO/tool.sh"
git -C "$REPO" add .gitignore
git -C "$REPO" add -f tool.sh
git -C "$REPO" commit -q -m ignored --no-verify
expect "a pushed force-added gitignored file is verified" \
  "1|tool.sh:1: cli-flag-verify: unknown flag(s) in tool.sh, unverified, not proven wrong: the installed --help may predate the flag." \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"

new_repo
printf 'faketool --bogus in a text file\n' >"$REPO/notes.txt"
commit_all notes
expect "a file type the verifiers do not read passes" "0|" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"

new_repo
git -C "$REPO" checkout -q -b topic
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all topic
expect "a new branch ranges from its merge-base with origin's default branch" "1|run.sh:3: $FLAG_FINDING" \
  "$(push_check refs/heads/topic "$(git -C "$REPO" rev-parse HEAD)" "$ZERO")"
expect "a branch deletion checks nothing" "0|" "$(push_check refs/heads/topic "$ZERO" "$BASE")"

new_repo
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
expect "--worktree: an uncommitted unknown flag blocks" 1 "$(c="$(worktree_check)" && printf '%s' "${c%%|*}")"
git -C "$REPO" checkout -q run.sh
expect "--worktree: no uncommitted change passes" "0|" "$(worktree_check)"

# End to end through the plugin's vendored installer, a real commit and a real push.
new_repo
status="$(node "$INSTALL" copy --scope local --entry reference-verify --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"reference-verify","status":"installed"}]' "$status"
expect "the entry is registered as a pre-push hook" yes \
  "$(test -f "$REPO/.git/hooks/pre-push.d/guardrails.reference-verify" && test ! -e "$REPO/.git/hooks/pre-commit" && echo yes)"
for a in run-guards.sh hook-utils.sh cli-flag-verify.sh verify-cli-flag.sh; do
  expect "the $a asset is installed beside the copy" yes "$(test -f "$REPO/.git/hooks/guardrails/$a" && echo yes)"
done
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
git -C "$REPO" commit -q -m change 2>/dev/null
expect "git commit does not run the entry" 0 "$?"
err="$(git -C "$REPO" push -q origin main 2>&1)"
expect "git push runs the installed entry and fails on the added flag" 1 "$?"
expect "the installed copy finds its verifier (the finding names the flag)" yes \
  "$(grep -q 'faketool --bogus' <<<"$err" && echo yes)"
printf '#!/usr/bin/env bash\nfaketool --real\necho clean\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
git -C "$REPO" commit -q -m clean 2>/dev/null
git -C "$REPO" push -q origin main 2>/dev/null
expect "a push whose net change adds no finding passes through the installed entry" 0 "$?"
expect "verify reports the entry ok" "ok	reference-verify" "$(node "$INSTALL" verify --repo "$REPO" | grep 'reference-verify')"

echo "reference-verify: $PASS passed, $FAIL failed"
((FAIL == 0))
