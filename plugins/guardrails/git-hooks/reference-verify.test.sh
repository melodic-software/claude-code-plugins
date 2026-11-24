#!/usr/bin/env bash
# test-scope: plugins/guardrails/git-hooks/entries.json plugins/guardrails/hooks/run-guards.sh plugins/guardrails/hooks/cli-flag-verify.sh plugins/guardrails/hooks/stale-path-verify.sh plugins/guardrails/hooks/skill-reference-verify.sh plugins/guardrails/lib/git-hooks/install.mjs plugins/guardrails/lib/git-hooks/check-lib.sh plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/git-hooks/commit-msg-convention.sh plugins/guardrails/git-hooks/pre-commit-content.sh
# test-scope: plugins/guardrails/hooks/*.sh plugins/guardrails/lib/verification/*.sh plugins/guardrails/lib/git-hooks-test-helpers.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/reference-verify.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH -- reference-verify tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

mkdir -p "$WORK/bin" "$WORK/cache"
# shellcheck disable=SC2016 # the fake tool's script text: its $ expands when it runs, not here
printf '#!/usr/bin/env bash\nfor a in "$@"; do last="$a"; done\n[[ "$last" == --help ]] && echo "  --real  a real flag"\nexit 0\n' \
  >"$WORK/bin/faketool"
chmod +x "$WORK/bin/faketool"
export PATH="$WORK/bin:$PATH" CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool
export XDG_CACHE_HOME="$WORK/cache" LOCALAPPDATA="$WORK/cache"

# shellcheck source=../lib/git-hooks-test-helpers.sh
source "$PLUGIN/lib/git-hooks-test-helpers.sh"

ZERO=0000000000000000000000000000000000000000
n=0
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

commit_all() {
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "$1" --no-verify
}

push_check() {
  local err rc
  err="$(cd "$REPO" && printf '%s %s %s %s\n' "$1" "$2" "$1" "$3" |
    bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(head -1 <<<"$err")"
}

push_lines() {
  local err rc
  err="$(cd "$REPO" && bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(head -1 <<<"$err")"
}

push_err() {
  local err
  err="$(cd "$REPO" && printf '%s %s %s %s\n' "$1" "$2" "$1" "$3" |
    bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  printf '%s\n' "$err"
}

worktree_check() {
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
expect "the failure names the decline key the script reads" yes \
  "$(grep -qxF 'git config checks.guardrails.reference-verify.declined true' <<<"$err" && echo yes)"
expect "the failure says the skip key covers only a missing jq" yes \
  "$(grep -qF 'checks.skipmissing=jq' <<<"$err" && grep -qi 'only while jq is missing' <<<"$err" && echo yes)"

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

new_repo
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all bogus
tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" config checks.guardrails.reference-verify.declined true
expect "with the entry declined, a push checks nothing" "0|" "$(push_check refs/heads/main "$tip" "$BASE")"
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
expect "a range whose only finding is a stale path prints it and passes" \
  "0|README.md:1: stale-path-verify: cited path(s) in README.md were deleted from this repo:" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"
err="$(push_err refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"
expect "the stale-path finding names the path and says it does not fail the push" yes \
  "$(grep -qF 'README.md:1:   docs/gone.md' <<<"$err" && grep -qF 'advisory and does not fail the push' <<<"$err" && echo yes)"
expect "a stale-path-only push names no blocking fix" no \
  "$(grep -qF 'commit the fix, then push again' <<<"$err" && echo yes || echo no)"
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all bogus-too
expect "a stale path beside an unknown flag: the flag fails the push" "1|run.sh:3: $FLAG_FINDING" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"
err="$(push_err refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$BASE")"
expect "a stale path beside an unknown flag is still printed" yes \
  "$(grep -qF 'README.md:1: stale-path-verify' <<<"$err" && echo yes)"
expect "a push with a blocking finding names the fix" yes \
  "$(grep -qxF 'guardrails: correct each flag or skill reference above, or fix the failure a reference-verify line names, commit the fix, then push again.' <<<"$err" && echo yes || echo no)"

new_repo
mkdir -p "$REPO/plugins/alpha/.claude-plugin" "$REPO/plugins/alpha/skills/setup"
printf '{"name":"alpha","version":"0.1.0"}\n' >"$REPO/plugins/alpha/.claude-plugin/plugin.json"
: >"$REPO/plugins/alpha/skills/setup/SKILL.md"
commit_all marketplace
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf 'Run `/alpha:setup`, then `/alpha:missing`.\n' >"$REPO/NOTES.md"
commit_all skill-ref
expect "an unresolved skill reference fails the push" \
  "1|NOTES.md:1: skill-reference-verify: skill reference(s) in NOTES.md do not resolve; this repo owns the plugin:" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"

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
  "0|docs/new/README.md:24: stale-path-verify: cited path(s) in docs/new/README.md were deleted from this repo:" \
  "$(push_check refs/heads/main "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
mkdir -p "$WORK/fail-shims"
for t in awk git jq; do
  # shellcheck disable=SC2016 # $* and the SHIM_ variables expand when the shim runs
  printf '#!/bin/sh\ncase " $* " in\n*"$SHIM_FAIL"*)\n  c=$(($(cat "$SHIM_COUNT" 2>/dev/null || echo 0) + 1)); echo "$c" >"$SHIM_COUNT"\n  if [ "$c" -eq "${SHIM_NTH:-1}" ]; then echo "%s: fatal error: internal error" >&2; exit 2; fi ;;\nesac\nexec %s "$@"\n' \
    "$t" "$(command -v "$t")" >"$WORK/fail-shims/$t"
  chmod +x "$WORK/fail-shims/$t"
done
push_failing() {
  local err rc
  rm -f "$WORK/shim-count"
  err="$(cd "$REPO" && printf '%s %s %s %s\n' "$3" "$4" "$3" "$5" |
    PATH="$WORK/fail-shims:$PATH" SHIM_FAIL="$1" SHIM_NTH="$2" SHIM_COUNT="$WORK/shim-count" \
      bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(grep -F 'reference-verify.sh: ' <<<"$err")"
}
tip="$(git -C "$REPO" rev-parse HEAD)"
expect "a git diff that fails while listing a copy's lines fails the push" \
  "1|reference-verify.sh: git exited 2 while listing the lines a copy adds, so this change was not fully checked; fix that failure, then push again" \
  "$(push_failing '--diff-filter=C --src-prefix' 1 refs/heads/main "$tip" "$pushed")"
expect "an awk that fails while listing a copy's lines fails the push" \
  "1|reference-verify.sh: awk exited 2 while listing the lines a copy adds, so this change was not fully checked; fix that failure, then push again" \
  "$(push_failing 'path ~ /^b' 2 refs/heads/main "$tip" "$pushed")"
# shellcheck disable=SC2016 # the marker is the awk program's literal text
expect "an awk that fails while merging a copy's lines fails the push" \
  "1|reference-verify.sh: awk exited 2 while merging the lines a copy adds into the changed lines, so this change was not fully checked; fix that failure, then push again" \
  "$(push_failing 'copy[$0] = 1' 1 refs/heads/main "$tip" "$pushed")"

push_unchecked() {
  local err rc
  rm -f "$WORK/shim-count"
  err="$(cd "$REPO" && printf '%s %s %s %s\n' "$2" "$3" "$2" "$4" |
    PATH="$WORK/fail-shims:$PATH" SHIM_FAIL="$1" SHIM_COUNT="$WORK/shim-count" \
      bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(grep -m1 -F ': reference-verify: ' <<<"$err")"
}
new_repo
printf '#!/usr/bin/env bash\nfaketool --real\n' >"$REPO/clean.sh"
commit_all clean-new
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nfaketool --real\necho more\n' >"$REPO/clean.sh"
printf '# Fresh\n\nNew notes, unlike any other file here.\n' >"$REPO/fresh.md"
commit_all clean-edit
tip="$(git -C "$REPO" rev-parse HEAD)"
expect "the clean push passes without a failing tool" "0|" "$(push_check refs/heads/main "$tip" "$pushed")"
expect "a jq that fails while building a new file's input fails the push, naming the file" \
  "1|fresh.md:1: reference-verify: jq exited 2 while building the verifiers' input, so it was not checked; fix that failure, then push again." \
  "$(push_unchecked 'tool_name: "Write"' refs/heads/main "$tip" "$pushed")"
expect "a jq that fails while building a changed file's input fails the push, naming the file" \
  "1|clean.sh:3: reference-verify: jq exited 2 while building the verifiers' input, so it was not checked; fix that failure, then push again." \
  "$(push_unchecked 'tool_name: "Edit"' refs/heads/main "$tip" "$pushed")"
expect "a jq that fails while reading the verifiers' output fails the push, naming the file" \
  "1|clean.sh:3: reference-verify: jq exited 2 while reading the verifiers' output, so it was not checked; fix that failure, then push again." \
  "$(push_unchecked '-r .hookSpecificOutput.additionalContext' refs/heads/main "$tip" "$pushed")"
plugin_copy() {
  mkdir -p "$1/hooks" "$1/git-hooks"
  ln -s "$PLUGIN/lib" "$1/lib"
  ln -s "$CHECK" "$1/git-hooks/reference-verify.sh"
  for f in "$PLUGIN"/hooks/*; do ln -s "$f" "$1/hooks/${f##*/}"; done
}
plugin_copy "$WORK/broken"
rm "$WORK/broken/hooks/run-guards.sh"
printf 'exit 3\n' >"$WORK/broken/hooks/run-guards.sh"
err="$(cd "$REPO" && printf 'refs/heads/main %s refs/heads/main %s\n' "$tip" "$pushed" |
  bash "$WORK/broken/git-hooks/reference-verify.sh" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
expect "a verifier run that exits non-zero fails the push, naming the file" \
  "1|clean.sh:3: reference-verify: run-guards.sh exited 3 while running the verifiers, so it was not checked; fix that failure, then push again." \
  "$?|$(grep -m1 -F ': reference-verify: ' <<<"$err")"

new_repo
git -C "$REPO" checkout -q -b side
printf '#!/usr/bin/env bash\nfaketool --real\n' >"$REPO/side.sh"
commit_all side
tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q main
expect "a clean pushed tip passes when it can be checked out" "0|" "$(push_check refs/heads/side "$tip" "$ZERO")"
expect "a pushed tip that cannot be checked out fails the push, naming the tip" \
  "1|$tip: reference-verify: could not check out this pushed tip, so its range was not checked; fix that failure (disk space, a lock under .git/worktrees), then push again." \
  "$(push_unchecked 'worktree add' refs/heads/side "$tip" "$ZERO")"
expect "the failed checkout leaves no worktree behind" 1 "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')"

new_readme_repo() {
  new_repo
  printf '# R\n' >"$REPO/README.md"
  commit_all readme
  git -C "$REPO" push -q --no-verify origin main 2>/dev/null
}

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
expect "a pushed tip that deletes a cited path is reported though the checkout has it" \
  "0|README.md:2: stale-path-verify: cited path(s) in README.md were deleted from this repo:" \
  "$(push_check refs/heads/drop "$tip" "$ZERO")"

new_repo
git -C "$REPO" checkout -q -b fresh
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf 'See `docs/gone.md` for the details.\n' >"$REPO/NEW.md"
commit_all fresh
tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q main
expect "a file the checkout lacks is judged from the pushed tip" \
  "0|NEW.md:1: stale-path-verify: cited path(s) in NEW.md were deleted from this repo:" \
  "$(push_check refs/heads/fresh "$tip" "$ZERO")"

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
expect "an awk that fails while narrowing to the branch's lines fails the push" \
  "1|reference-verify.sh: awk exited 2 while narrowing the changed lines to the branch, so this change was not fully checked; fix that failure, then push again" \
  "$(push_failing 'NR == FNR { n++; f[n]' 1 refs/heads/topic "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
git -C "$REPO" checkout -q main

plugin_copy "$WORK/counting"
mv "$WORK/counting/hooks/run-guards.sh" "$WORK/counting/hooks/run-guards-real.sh"
cat >"$WORK/counting/hooks/run-guards.sh" <<'EOF'
#!/usr/bin/env bash
payload="$(cat)"
jq -r '.tool_input.file_path' <<<"$payload" | sed 's#.*/##' >>"$JUDGED_LOG"
exec bash "${BASH_SOURCE[0]%/*}/run-guards-real.sh" "$@" <<<"$payload"
EOF
judged_files() {
  : >"$WORK/judged"
  (cd "$REPO" && printf '%s %s %s %s\n' "$1" "$2" "$1" "$3" |
    JUDGED_LOG="$WORK/judged" bash "$WORK/counting/git-hooks/reference-verify.sh" origin "$WORK/r$n.git" >/dev/null 2>&1)
  sort "$WORK/judged" | tr '\n' ' ' | sed 's/ $//'
}
new_repo
git -C "$REPO" checkout -q -b integ
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
printf '#!/usr/bin/env bash\nfaketool --bogus\n' >"$REPO/integ-new.sh"
commit_all integ-bogus
git -C "$REPO" push -q --no-verify origin integ 2>/dev/null
git -C "$REPO" checkout -q -b delivery main
printf '#!/usr/bin/env bash\nfaketool --real\n' >"$REPO/delivery.sh"
commit_all delivery
git -C "$REPO" push -q --no-verify origin delivery 2>/dev/null
pushed="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" merge -q --no-ff --no-edit --no-verify integ >/dev/null
merged="$(git -C "$REPO" rev-parse HEAD)"
expect "a branch that merged a pushed non-default branch is not judged on that branch's lines" "0|" \
  "$(push_check refs/heads/delivery "$merged" "$pushed")"
expect "the merge push runs the verifiers on no file the merged branch changed" "" \
  "$(judged_files refs/heads/delivery "$merged" "$pushed")"
git -C "$REPO" reset -q --hard "$pushed"
git -C "$REPO" merge -q --no-ff --no-commit integ >/dev/null 2>&1
printf 'faketool --merged\n' >>"$REPO/integ-new.sh"
commit_all merge-resolution
expect "a line the merge resolution adds to a merged branch's file is judged, at that line" \
  "1|integ-new.sh:3: ${FLAG_FINDING/in run.sh/in integ-new.sh}" \
  "$(push_check refs/heads/delivery "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
git -C "$REPO" reset -q --hard "$merged"
printf '#!/usr/bin/env bash\nfaketool --bogus\n' >"$REPO/own-new.sh"
printf 'echo more\n' >>"$REPO/delivery.sh"
commit_all delivery-own
tip="$(git -C "$REPO" rev-parse HEAD)"
expect "after merging a pushed branch, a file the branch adds is judged" "1|own-new.sh:2: ${FLAG_FINDING/in run.sh/in own-new.sh}" \
  "$(push_check refs/heads/delivery "$tip" "$pushed")"
expect "the push runs the verifiers only on the files the branch's own commits change" "delivery.sh own-new.sh" \
  "$(judged_files refs/heads/delivery "$tip" "$pushed")"
git -C "$REPO" reset -q --hard integ
expect "a branch reset to a pushed branch's tip is not judged on its lines" "0|" \
  "$(push_check refs/heads/delivery "$(git -C "$REPO" rev-parse HEAD)" "$pushed")"
git -C "$REPO" checkout -q main

new_repo
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
expect "--worktree: an uncommitted unknown flag blocks" 1 "$(c="$(worktree_check)" && printf '%s' "${c%%|*}")"
git -C "$REPO" checkout -q run.sh
expect "--worktree: no uncommitted change passes" "0|" "$(worktree_check)"

base_check() {
  local err rc
  err="$(cd "$REPO" && bash "$CHECK" --base "$1" 2>&1 >/dev/null </dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(head -1 <<<"$err")"
}
new_repo
git -C "$REPO" checkout -q -b pushed-feature
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
commit_all pushed-bogus
git -C "$REPO" push -q --no-verify origin pushed-feature 2>/dev/null
tip="$(git -C "$REPO" rev-parse HEAD)"
expect "refs on stdin skip a branch whose commits the remote already has" "0|" \
  "$(push_check refs/heads/pushed-feature "$tip" "$ZERO")"
expect "--base judges every commit from the merge-base, pushed ones included" "1|run.sh:3: $FLAG_FINDING" \
  "$(base_check origin/main)"
git -C "$REPO" checkout -q main
expect "--base on a branch that adds nothing passes" "0|" "$(base_check origin/main)"
expect "--base with no ref is a usage error" 2 \
  "$(cd "$REPO" && bash "$CHECK" --base >/dev/null 2>&1 </dev/null; echo "$?")"

new_repo
WT="$WORK/wt$n"
git -C "$REPO" worktree add -q -b restore "$WT" main
mkdir -p "$WT/docs/sub"
printf 'gone\n' >"$WT/docs/gone.md"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf '# R\nSee `docs/gone.md` for the details.\n' >"$WT/docs/sub/README.md"
git -C "$WT" add -A
git -C "$WT" commit -q -m restore --no-verify
err="$(cd "$WT" && printf 'refs/heads/restore %s refs/heads/restore %s\n' "$(git rev-parse HEAD)" "$ZERO" |
  GIT_DIR="$(git rev-parse --absolute-git-dir)" bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
expect "a run from a linked worktree citing a restored path passes" "0|" "$?|$(head -1 <<<"$err")"

new_repo
WT="$WORK/wt$n"
git -C "$REPO" worktree add -q -b cite "$WT" main
mkdir -p "$WT/docs/sub"
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf '# R\nSee `docs/gone.md` for the details.\n' >"$WT/docs/sub/README.md"
git -C "$WT" add -A
git -C "$WT" commit -q -m cite --no-verify
err="$(cd "$WT" && printf 'refs/heads/cite %s refs/heads/cite %s\n' "$(git rev-parse HEAD)" "$ZERO" |
  GIT_CEILING_DIRECTORIES="$WT/docs" bash "$CHECK" origin "$WORK/r$n.git" 2>&1)"
expect "a run under a discovery ceiling citing a deleted path reports it" "0|yes" \
  "$?|$(grep -qF 'docs/sub/README.md:2: stale-path-verify' <<<"$err" && echo yes)"

echo "reference-verify: $PASS passed, $FAIL failed"
((FAIL == 0))
