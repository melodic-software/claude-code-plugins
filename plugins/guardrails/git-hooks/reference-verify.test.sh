#!/usr/bin/env bash
# Contract tests for the guardrails pre-push entry git-hooks/reference-verify.sh:
# an unknown CLI flag or a cited path the repository deleted, on a line the
# pushed commits add, blocks with "<path>:<line>: <message>", the line the text
# is on; a declined entry checks nothing, run directly or through the
# lefthook-remote wrapper; the same text on an
# unchanged line, in a file type the verifiers do not read, or in an eval
# suite's samples/ folder (recorded model output), does not; a new
# branch ranges from its merge-base with the remote's default branch, or from a
# pushed branch it is stacked on, a pushed branch that merged main is judged
# only on its own lines, and a deletion checks nothing; the failure names the
# way out (decline the entry; the skip key covers only a missing jq);
# --worktree covers uncommitted files;
# and the plugin's vendored installer wires the entry as a pre-push hook, so
# `git commit` does not run it and `git push` does.
# test-scope: plugins/guardrails/git-hooks/entries.json plugins/guardrails/hooks/run-guards.sh plugins/guardrails/hooks/cli-flag-verify.sh plugins/guardrails/hooks/stale-path-verify.sh plugins/guardrails/hooks/skill-reference-verify.sh plugins/guardrails/lib/git-hooks/install.mjs plugins/guardrails/lib/git-hooks/check-lib.sh plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/git-hooks/commit-msg-convention.sh plugins/guardrails/git-hooks/pre-commit-content.sh .lefthook/pre-push/guardrails-reference-verify.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA
# Env-supplied config (a caller's core.hooksPath, say) would reach every repo below.
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/reference-verify.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
TOP="$(cd "$PLUGIN/../.." && pwd)"
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

push_lines() { # stdin: pre-push ref lines -> "<rc>|<first stderr line>"
  local err rc
  err="$(cd "$REPO" && bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
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

# A changed file whose name git quotes has no entry in the range table: it is
# judged whole instead of skipped. Windows refuses the name.
new_repo
if printf '#!/usr/bin/env bash\nfaketool --real\n' 2>/dev/null >"$REPO/a\"b.sh"; then
  commit_all quoted-name
  BASE="$(git -C "$REPO" rev-parse HEAD)"
  printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/a\"b.sh"
  commit_all quoted-bogus
  expect "an unknown flag in a changed file whose name git quotes blocks, at its line" "1|a\"b.sh:3: ${FLAG_FINDING/in run.sh/in a\"b.sh}" \
    "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"
else
  echo "skip: this file system refuses a name holding a double quote"
fi

err="$(push_err refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"
expect "the failure names the decline route for this entry" yes \
  "$(grep -qF 'install.mjs decline --entry reference-verify' <<<"$err" && grep -qF '/guardrails:setup' <<<"$err" && echo yes)"
expect "the failure says the skip key covers only a missing jq" yes \
  "$(grep -qF 'checks.skipmissing=jq' <<<"$err" && grep -qi 'only while jq is missing' <<<"$err" && echo yes)"

# A finding names the line its text is on, not the file's first added line.
new_repo
printf '#!/usr/bin/env bash\nfaketool --real\necho a\necho b\n' >"$REPO/run.sh"
commit_all four
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nfaketool --real\necho changed\necho b\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all two-hunks
expect "with two added hunks, a finding in the second names its line" "1|run.sh:5: $FLAG_FINDING" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
new_repo
mkdir -p "$REPO/docs"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf '# S\n\nIntro.\n\nRun `faketool --bogus` here.\n' >"$REPO/docs/guide.md"
commit_all guide
expect "a new markdown file's finding names its code span's line, heading and detail" \
  "docs/guide.md:5: ${FLAG_FINDING/in run.sh/in docs/guide.md}
docs/guide.md:5:   faketool --bogus (not in 'faketool --help')" \
  "$(push_err refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE" | head -2)"

# A declined entry checks nothing, run directly or through the lefthook-remote
# wrapper from a fetched copy: the entry's key, else the master key, at git's
# precedence, so the entry's false beats the master's true.
REMOTE="$WORK/lefthook/info/lefthook-remotes/r"
mkdir -p "$REMOTE/.lefthook/pre-push" "$REMOTE/plugins"
cp "$TOP/.lefthook/pre-push/guardrails-reference-verify.sh" "$REMOTE/.lefthook/pre-push/"
cp -R "$PLUGIN" "$REMOTE/plugins/guardrails"
via_wrapper() { # <ref> <local-sha> <remote-sha> -> "<rc>|<first stderr line>"
  local err rc
  err="$(cd "$REPO" && printf '%s %s %s %s\n' "$1" "$2" "$1" "$3" |
    sh "$REMOTE/.lefthook/pre-push/guardrails-reference-verify.sh" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(head -1 <<<"$err")"
}
new_repo
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all bogus
tip="$(git -C "$REPO" rev-parse HEAD)"
expect "the lefthook-remote wrapper runs the check" "1|run.sh:3: $FLAG_FINDING" \
  "$(via_wrapper refs/heads/main "$tip" "$BASE")"
git -C "$REPO" config checks.guardrails.reference-verify.declined true
expect "with the entry declined, a push checks nothing" "0|" "$(push_check refs/heads/main "$tip" "$BASE")"
expect "with the entry declined, the lefthook-remote wrapper checks nothing" "0|" \
  "$(via_wrapper refs/heads/main "$tip" "$BASE")"
git -C "$REPO" config --unset checks.guardrails.reference-verify.declined
git -C "$REPO" config checks.git-hooks.declined true
expect "with every entry declined by the master key, a push checks nothing" "0|" \
  "$(push_check refs/heads/main "$tip" "$BASE")"
git -C "$REPO" config checks.guardrails.reference-verify.declined false
expect "the entry's false beats the master key's true" "1|run.sh:3: $FLAG_FINDING" \
  "$(push_check refs/heads/main "$tip" "$BASE")"

new_repo
printf '#!/usr/bin/env bash\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all old
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nfaketool --bogus\necho fine\n' >"$REPO/run.sh"
commit_all more
expect "an unknown flag on a line an earlier push added does not block" "0|" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" mv run.sh tool.sh
commit_all rename
expect "a pure rename adds no line, so an earlier unknown flag does not block" "0|" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"

# Two pushed refs change one file: each range is judged on its own tip's blob.
new_repo
git -C "$REPO" switch -q -c clean
printf '#!/usr/bin/env bash\nfaketool --real\necho fine\n' >"$REPO/run.sh"
commit_all clean
clean_tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" switch -q -c bogus "$BASE"
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all bogus
bogus_tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" switch -q main
expect "with two pushed refs changing one file, each is read from its own tip" "1|run.sh:3: $FLAG_FINDING" \
  "$(printf 'refs/heads/clean %s refs/heads/clean %s\nrefs/heads/bogus %s refs/heads/bogus %s\n' \
    "$clean_tip" "$ZERO" "$bogus_tip" "$ZERO" | push_lines)"
expect "with the clean ref alone, nothing blocks" "0|" \
  "$(printf 'refs/heads/clean %s refs/heads/clean %s\n' "$clean_tip" "$ZERO" | push_lines)"
# This entry sets its own EXIT trap; a lib awk that fails while listing the
# changed lines must still fail the push, though the push adds no finding.
mkdir -p "$WORK/shims"
# shellcheck disable=SC2016 # $* expands when the shim runs
printf '#!/bin/sh\ncase " $* " in\n*"/^\\+\\+\\+ /"*) echo "awk: fatal error: internal error" >&2; exit 2 ;;\nesac\nexec %s "$@"\n' \
  "$(command -v awk)" >"$WORK/shims/awk"
chmod +x "$WORK/shims/awk"
err="$(cd "$REPO" && printf 'refs/heads/clean %s refs/heads/clean %s\n' "$clean_tip" "$ZERO" |
  PATH="$WORK/shims:$PATH" bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
expect "a lib awk that fails while listing the changed lines fails the push" \
  "1|reference-verify.sh: awk exited 2 while listing the changed lines, so this change was not fully checked; fix that failure, then push again" \
  "$?|$(grep -F 'reference-verify.sh: awk exited' <<<"$err")"
expect "the failing push still leaves no worktree behind" 1 "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')"

new_repo
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf 'See `docs/gone.md` for the details.\n' >"$REPO/README.md"
commit_all readme
expect "a new file citing a deleted repository path blocks" \
  "1|README.md:1: stale-path-verify: cited path(s) in README.md were deleted from this repo:" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"

# A file over the kernel's per-argument limit (128 KiB on Linux) is judged, not
# skipped: its text never travels as one argument.
new_repo
{
  printf '#!/usr/bin/env bash\n'
  for ((i = 0; i < 2500; i++)); do printf 'echo "filler line %05d, padding the file past the argument limit"\n' "$i"; done
  printf 'faketool --bogus\n'
} >"$REPO/big.sh"
commit_all big
expect "a new file over 128 KiB is judged (the fixture is over the limit)" yes \
  "$(test "$(wc -c <"$REPO/big.sh")" -gt 131072 && echo yes)"
expect "an unknown flag in a new file over 128 KiB blocks, at its line" "1|big.sh:2502: ${FLAG_FINDING/in run.sh/in big.sh}" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"

# A doc moved with a stub left at its old path is a copy, not a rename (the old
# path is changed, the new one added): only the lines the move adds are judged,
# so a citation the doc already held, here a deletion record, passes.
new_repo
mkdir -p "$REPO/docs/old"
{
  printf '# Topic\n\n'
  for ((i = 1; i <= 10; i++)); do printf 'Paragraph %d of the topic, unchanged by the move.\n\n' "$i"; done
  # shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
  printf 'The `docs/gone.md` page was removed.\n'
} >"$REPO/docs/old/README.md"
commit_all topic
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
mkdir -p "$REPO/docs/new"
cp "$REPO/docs/old/README.md" "$REPO/docs/new/README.md"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf '# Topic\n\nMoved to `docs/new/README.md`.\n' >"$REPO/docs/old/README.md"
commit_all move
expect "a moved doc is judged on the lines the move adds, so a citation it held passes" "0|" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf 'See `docs/gone.md` for the details.\n' >>"$REPO/docs/new/README.md"
commit_all move-cites
expect "a line the move adds to the moved doc is judged, at that line" \
  "1|docs/new/README.md:24: stale-path-verify: cited path(s) in docs/new/README.md were deleted from this repo:" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"

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
  "1|tool.sh:2: cli-flag-verify: unknown flag(s) in tool.sh, unverified, not proven wrong: the installed --help may predate the flag." \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"

new_repo
printf 'faketool --bogus in a text file\n' >"$REPO/notes.txt"
commit_all notes
expect "a file type the verifiers do not read passes" "0|" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"

# An eval suite's samples/ folder holds recorded model output, so it is not
# verified; the suite's other files and a samples/ folder outside evals/ are.
# eval_case <path> -> "<rc>|<path before the first colon of the first finding>"
eval_case() {
  local c rest
  new_repo
  mkdir -p "$REPO/${1%/*}"
  # shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
  printf 'Run `faketool --bogus` here.\n' >"$REPO/$1"
  commit_all eval-case
  c="$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"
  rest="${c#*|}"
  printf '%s|%s' "${c%%|*}" "${rest%%:*}"
}
for p in plugins/p/evals/c/samples/answer.md evals/sources/labels/T1/samples/run1.md evals/samples/x.md; do
  expect "an unknown flag in the eval sample $p does not block" "0|" "$(eval_case "$p")"
done
for p in plugins/p/evals/c/graders/check.md plugins/p/evals/c/prompt.md docs/samples/x.md myevals/samples/x.md; do
  expect "an unknown flag in $p blocks" "1|$p" "$(eval_case "$p")"
done

new_repo
git -C "$REPO" checkout -q -b topic
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all topic
expect "a new branch ranges from its merge-base with origin's default branch" "1|run.sh:3: $FLAG_FINDING" \
  "$(push_check refs/heads/topic "$(git -C "$REPO" rev-parse HEAD)" "$ZERO")"
expect "a branch deletion checks nothing" "0|" "$(push_check refs/heads/topic "$ZERO" "$BASE")"

# A new branch stacked on a pushed branch is judged only on what it adds to that
# branch: the pushed branch's files are not verified again.
new_repo
git -C "$REPO" checkout -q -b phase1
printf '#!/usr/bin/env bash\nfaketool --bogus\n' >"$REPO/phase1.sh"
commit_all phase1
git -C "$REPO" checkout -q -b phase2
printf '#!/usr/bin/env bash\nfaketool --real\n' >"$REPO/phase2.sh"
commit_all phase2
expect "a new branch on an unpushed branch verifies that branch's files too" "1|phase1.sh:2: ${FLAG_FINDING/in run.sh/in phase1.sh}" \
  "$(push_check refs/heads/phase2 "$(git -C "$REPO" rev-parse HEAD)" "$ZERO")"
git -C "$REPO" push -q --no-verify origin phase1 2>/dev/null
expect "a new branch stacked on a pushed branch does not verify that branch's files" "0|" \
  "$(push_check refs/heads/phase2 "$(git -C "$REPO" rev-parse HEAD)" "$ZERO")"
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/phase2.sh"
commit_all phase2-bogus
expect "a new stacked branch is judged on the lines it adds" "1|phase2.sh:3: ${FLAG_FINDING/in run.sh/in phase2.sh}" \
  "$(push_check refs/heads/phase2 "$(git -C "$REPO" rev-parse HEAD)" "$ZERO")"
git -C "$REPO" checkout -q main

# A pushed branch that merged main: only the lines the branch itself adds are
# judged, never the ones the merge brought in from the default branch.
new_repo
git -C "$REPO" checkout -q -b topic
printf '#!/usr/bin/env bash\nfaketool --real\n' >"$REPO/topic.sh"
commit_all topic
git -C "$REPO" push -q --no-verify origin topic 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q main
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
printf '#!/usr/bin/env bash\nfaketool --bogus\n' >"$REPO/main-new.sh"
commit_all main-bogus
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
git -C "$REPO" checkout -q topic
git -C "$REPO" merge -q --no-edit --no-verify main >/dev/null
expect "a branch that merged main is not judged on the lines main added" "0|" \
  "$(push_check refs/heads/topic "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/topic.sh"
commit_all topic-bogus
expect "after merging main, a line the branch adds is still judged" "1|topic.sh:3: ${FLAG_FINDING/in run.sh/in topic.sh}" \
  "$(push_check refs/heads/topic "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
git -C "$REPO" checkout -q main

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

# git exports GIT_DIR to a hook, a linked worktree's git dir when pushed from
# one. A doc below the root citing a path the branch restored still passes.
new_repo
node "$INSTALL" copy --scope local --entry reference-verify --repo "$REPO" >/dev/null
WT="$WORK/wt$n"
git -C "$REPO" worktree add -q -b restore "$WT" main
mkdir -p "$WT/docs/sub"
printf 'gone\n' >"$WT/docs/gone.md"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf '# R\nSee `docs/gone.md` for the details.\n' >"$WT/docs/sub/README.md"
git -C "$WT" add -A
git -C "$WT" commit -q -m restore --no-verify
err="$(git -C "$WT" push -q origin restore 2>&1)"
expect "a push from a linked worktree citing a restored path passes" "0|" "$?|$(head -1 <<<"$err")"

# An inherited discovery ceiling between the doc and the root does not hide the
# repository, so a citation of a deleted path still blocks.
new_repo
node "$INSTALL" copy --scope local --entry reference-verify --repo "$REPO" >/dev/null
WT="$WORK/wt$n"
git -C "$REPO" worktree add -q -b cite "$WT" main
mkdir -p "$WT/docs/sub"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf '# R\nSee `docs/gone.md` for the details.\n' >"$WT/docs/sub/README.md"
git -C "$WT" add -A
git -C "$WT" commit -q -m cite --no-verify
GIT_CEILING_DIRECTORIES="$WT/docs" git -C "$WT" push -q origin cite >/dev/null 2>&1
expect "a push under a discovery ceiling citing a deleted path blocks" 1 "$?"

echo "reference-verify: $PASS passed, $FAIL failed"
((FAIL == 0))
