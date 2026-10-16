#!/usr/bin/env bash
# Contract tests for the guardrails pre-commit entry git-hooks/reference-verify.sh:
# an unknown CLI flag or a cited path the repository deleted, on a line the
# commit adds, blocks with "<path>:<line>: <message>"; the same text on an
# unchanged line, or in a file type the verifiers do not read, does not;
# --worktree covers uncommitted files; and the plugin's vendored installer wires
# the entry with its verifier assets so `git commit` runs it from the copy.
# test-scope: plugins/guardrails/git-hooks/entries.json plugins/guardrails/hooks/run-guards.sh plugins/guardrails/hooks/cli-flag-verify.sh plugins/guardrails/hooks/stale-path-verify.sh plugins/guardrails/hooks/skill-reference-verify.sh plugins/guardrails/lib/git-hooks/install.mjs
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

n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
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
}

check() { # <repo> [args...] -> "<rc>|<first stderr line>"
  local repo="$1" err rc
  shift
  err="$(cd "$repo" && bash "$CHECK" "$@" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(head -1 <<<"$err")"
}

new_repo
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
got="$(check "$REPO")"
expect "an unknown flag on an added line blocks, at that line" "1|run.sh:3: cli-flag-verify: unknown flag(s) in run.sh, unverified, not proven wrong: the installed --help may predate the flag." "$got"

new_repo
printf '#!/usr/bin/env bash\nfaketool --bogus\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
git -C "$REPO" commit -q -m old --no-verify
printf '#!/usr/bin/env bash\nfaketool --bogus\necho fine\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
expect "an unknown flag on an unchanged line does not block" "0|" "$(check "$REPO")"

new_repo
# shellcheck disable=SC2016 # markdown code-span backticks, literal fixture text
printf 'See `docs/gone.md` for the details.\n' >"$REPO/README.md"
git -C "$REPO" add README.md
expect "a new file citing a deleted repository path blocks" \
  "1|README.md:1: stale-path-verify: cited path(s) in README.md were deleted from this repo:" "$(check "$REPO")"

new_repo
printf 'faketool --bogus in a text file\n' >"$REPO/notes.txt"
git -C "$REPO" add notes.txt
expect "a file type the verifiers do not read passes" "0|" "$(check "$REPO")"

new_repo
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
expect "--worktree: an uncommitted unknown flag blocks" 1 "$(c="$(check "$REPO" --worktree)" && printf '%s' "${c%%|*}")"
git -C "$REPO" checkout -q run.sh
expect "--worktree: no uncommitted change passes" "0|" "$(check "$REPO" --worktree)"

# End to end through the plugin's vendored installer and a real commit.
new_repo
status="$(node "$INSTALL" copy --scope local --entry reference-verify --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"reference-verify","status":"installed"}]' "$status"
for a in run-guards.sh hook-utils.sh cli-flag-verify.sh verify-cli-flag.sh; do
  expect "the $a asset is installed beside the copy" yes "$(test -f "$REPO/.git/hooks/guardrails/$a" && echo yes)"
done
printf '#!/usr/bin/env bash\nfaketool --real\nfaketool --bogus\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
err="$(git -C "$REPO" commit -q -m change 2>&1)"
expect "git commit runs the installed entry and fails on the added flag" 1 "$?"
expect "the installed copy finds its verifier (the finding names the flag)" yes \
  "$(grep -q 'faketool --bogus' <<<"$err" && echo yes)"
printf '#!/usr/bin/env bash\nfaketool --real\necho clean\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
git -C "$REPO" commit -q -m clean 2>/dev/null
expect "a clean commit passes through the installed entry" 0 "$?"
expect "verify reports the entry ok" "ok	reference-verify" "$(node "$INSTALL" verify --repo "$REPO" | grep 'reference-verify')"

echo "reference-verify: $PASS passed, $FAIL failed"
((FAIL == 0))
