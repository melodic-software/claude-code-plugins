#!/usr/bin/env bash
# Contract tests for the guardrails pre-commit entry (git-hooks/pre-commit-content.sh):
# a secret or machine-specific path on a line the commit adds blocks with
# "<path>:<line>: <message>"; one on an unchanged line, in an unstaged change,
# in a symlinked file, an ordinary binary, or under an exempt path does not;
# a token in a file holding a NUL byte, UTF-16LE text included, blocks; a staged
# gitignored file is judged and an untracked one is not; --worktree covers uncommitted and untracked files; and the plugin's vendored
# installer wires the entry, pattern libraries included, so `git commit` runs it.
# test-scope: plugins/guardrails/git-hooks/entries.json plugins/guardrails/lib/git-hooks/check-lib.sh plugins/guardrails/lib/git-hooks/install.mjs plugins/guardrails/lib/secret-detection/secret-patterns.sh plugins/guardrails/lib/path-detection/hardcoded-path-patterns.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/pre-commit-content.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"

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

# Fixtures are assembled at run time, so no real-shape token or machine path
# sits in this file's own bytes for a scanner to find. Never fold them into
# literals.
SL='/'
FAKE_GHP="ghp_$(printf 'A%.0s' {1..36})"
FAKE_OPENAI="sk-$(printf 'A%.0s' {1..20})"
FAKE_LINUX="${SL}home${SL}alice${SL}projects${SL}demo${SL}src${SL}main.sh"

n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  printf 'line one\nline two\n' >"$REPO/notes.md"
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

rc_of() { # <repo> [args...] -> rc
  local got
  got="$(check "$@")"
  printf '%s' "${got%%|*}"
}

HINT='guardrails: remove the secrets or machine-specific paths above from the change (use a placeholder, an environment variable or a portable path), then commit again.'

new_repo
printf 'line one\nline two\nclean addition\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "clean staged text passes" "0|" "$(check "$REPO")"

new_repo
printf 'line one\ntoken=%s\nline two\n' "$FAKE_GHP" >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "a token on an added line blocks, naming that line" "1|notes.md:2: secret or credential pattern: GitHub PAT
$HINT" "$(check "$REPO")"

new_repo
printf 'line one\nline two\nsee %s here\n' "$FAKE_LINUX" >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "a home path on an added line blocks, naming that line" "1|notes.md:3: machine-specific path (Linux user path detected)
$HINT" "$(check "$REPO")"

# The Edit semantics check-bash-file-changes used: only the lines the change adds.
new_repo
printf 'line one\ntoken=%s\n' "$FAKE_GHP" >"$REPO/notes.md"
git -C "$REPO" add notes.md
git -C "$REPO" commit -q -m old --no-verify
printf 'line one\ntoken=%s\nclean new line\n' "$FAKE_GHP" >"$REPO/notes.md"
git -C "$REPO" add notes.md
expect "a token on an unchanged line does not block" "0|" "$(check "$REPO")"

new_repo
printf 'brand new token=%s\n' "$FAKE_GHP" >"$REPO/new.txt"
git -C "$REPO" add new.txt
expect "a new file is judged whole" 1 "$(rc_of "$REPO")"

# A tracked `-diff` attribute makes numstat call a text file binary and the diff
# print no hunks; the bytes decide, so the token is still found.
new_repo
printf '*.yml -diff\n' >"$REPO/.gitattributes"
printf 'key: value\ntoken: %s\n' "$FAKE_GHP" >"$REPO/ci.yml"
git -C "$REPO" add .gitattributes ci.yml
expect "a token in a .yml file under a -diff attribute blocks, naming that line" "1|ci.yml:2: secret or credential pattern: GitHub PAT
$HINT" "$(check "$REPO")"
new_repo
printf '*.yml -diff\n' >"$REPO/.gitattributes"
printf 'key: value\n' >"$REPO/ci.yml"
git -C "$REPO" add .gitattributes ci.yml
git -C "$REPO" commit -q -m attrs --no-verify
printf 'key: value\nother: %s\n' "$FAKE_GHP" >"$REPO/ci.yml"
git -C "$REPO" add ci.yml
expect "a token added to a changed -diff file blocks, naming that line" "1|ci.yml:2: secret or credential pattern: GitHub PAT
$HINT" "$(check "$REPO")"
new_repo
printf 'MZ\0token=%s\n' "$FAKE_GHP" >"$REPO/blob.bin"
git -C "$REPO" add blob.bin
expect "a token in a file holding a NUL byte blocks" "1|blob.bin:1: secret or credential pattern: GitHub PAT
$HINT" "$(check "$REPO")"
expect "--worktree: a token in an untracked file holding a NUL byte blocks" 1 \
  "$(git -C "$REPO" rm -q --cached blob.bin && rc_of "$REPO" --worktree)"

# Git quotes a name holding `"` whatever core.quotePath says. Windows refuses
# the name, so the case runs where the file system takes it.
new_repo
if printf 'token=%s\n' "$FAKE_GHP" 2>/dev/null >"$REPO/a\"b.txt"; then
  git -C "$REPO" add -- "a\"b.txt"
  expect "a token in a file whose name git quotes blocks" 1 "$(rc_of "$REPO")"
else
  echo "skip: this file system refuses a name holding a double quote"
fi
new_repo
if printf 'see %s here\n' "$FAKE_LINUX" 2>/dev/null >"$REPO/a"$'\t'"b.txt"; then
  git -C "$REPO" add -- "a"$'\t'"b.txt"
  expect "a home path in a file whose name holds a tab blocks" 1 "$(rc_of "$REPO")"
else
  echo "skip: this file system refuses a name holding a tab"
fi

new_repo
printf 'line one\nline two\nstaged clean\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
printf 'line one\nline two\nstaged clean\ntoken=%s\n' "$FAKE_GHP" >"$REPO/notes.md"
expect "an unstaged token in a partly staged file does not block" "0|" "$(check "$REPO")"
printf 'line one\nline two\ntoken=%s\n' "$FAKE_GHP" >"$REPO/notes.md"
git -C "$REPO" add notes.md
printf 'line one\nline two\nfixed in the work tree\n' >"$REPO/notes.md"
expect "a staged token blocks though the work tree is fixed" 1 "$(rc_of "$REPO")"

new_repo
mkdir -p "$REPO/tests/fixtures"
printf 'token=%s\n' "$FAKE_GHP" >"$REPO/tests/fixtures/sample.env"
printf 'OPENAI_KEY=%s\n' "$FAKE_OPENAI" >"$REPO/.env.example"
git -C "$REPO" add -A
expect "secret exemptions hold: tests/fixtures and .env.example" "0|" "$(check "$REPO")"
printf 'see %s\n' "$FAKE_LINUX" >"$REPO/tests/fixtures/path.txt"
git -C "$REPO" add -A
expect "tests/fixtures is still scanned for machine paths" 1 "$(rc_of "$REPO")"

# A force-added ignored file is what the commit holds, and .env is the usual
# secret carrier.
new_repo
printf '.env\n' >"$REPO/.gitignore"
printf 'token=%s\n' "$FAKE_GHP" >"$REPO/.env"
git -C "$REPO" add .gitignore
git -C "$REPO" add -f .env
expect "a gitignored file force-added is judged" "1|.env:1: secret or credential pattern: GitHub PAT
$HINT" "$(check "$REPO")"
expect "--worktree: a tracked gitignored file is judged" 1 "$(rc_of "$REPO" --worktree)"
git -C "$REPO" rm -q --cached .env
expect "--worktree: an untracked gitignored file is not judged" "0|" "$(check "$REPO" --worktree)"

# secret-pattern-detection's path options exempt a Write, never a commit: an
# ignored file under an allowed root, force-added, still blocks with both set.
new_repo
mkdir -p "$REPO/notes"
printf 'notes/\n' >"$REPO/.gitignore"
printf 'token=%s\n' "$FAKE_GHP" >"$REPO/notes/keys.md"
git -C "$REPO" add .gitignore
git -C "$REPO" add -f notes/keys.md
expect "the Write-time path options do not exempt a commit" 1 \
  "$(cd "$REPO" && env CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ALLOWED_ROOTS="$REPO/notes" \
    CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_SKIP_GITIGNORED=true bash "$CHECK" >/dev/null 2>&1
  printf '%s' "$?")"

new_repo
ln -s "token=$FAKE_GHP" "$REPO/link.txt"
git -C "$REPO" add link.txt
expect "a symbolic link is not judged" "0|" "$(check "$REPO")"

# UTF-16LE (a Windows .reg export, PowerShell `>` output) puts a NUL after
# every ASCII byte.
new_repo
s="token=$FAKE_GHP"
{
  printf '\377\376'
  for ((i = 0; i < ${#s}; i++)); do printf '%s\0' "${s:i:1}"; done
  printf '\n\0'
} >"$REPO/export.reg"
git -C "$REPO" add export.reg
expect "a token in a UTF-16LE file blocks" "1|export.reg:1: secret or credential pattern: GitHub PAT
$HINT" "$(check "$REPO")"

new_repo
printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\001' >"$REPO/image.png"
git -C "$REPO" add image.png
expect "an ordinary binary with no secret still passes" "0|" "$(check "$REPO")"

new_repo
printf 'line one\nline two\ntoken=%s\n' "$FAKE_GHP" >"$REPO/notes.md"
expect "--worktree: an uncommitted token blocks" 1 "$(rc_of "$REPO" --worktree)"
git -C "$REPO" checkout -q notes.md
printf 'see %s\n' "$FAKE_LINUX" >"$REPO/loose.md"
expect "--worktree: an untracked file is judged whole" "1|loose.md:1: machine-specific path (Linux user path detected)
$HINT" "$(check "$REPO" --worktree)"
rm "$REPO/loose.md"
expect "--worktree: no uncommitted change passes" "0|" "$(check "$REPO" --worktree)"

# End to end through the plugin's vendored installer and a real commit.
new_repo
status="$(node "$INSTALL" copy --scope local --entry pre-commit-content --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"pre-commit-content","status":"installed"}]' "$status"
for a in secret-patterns.sh hardcoded-path-patterns.sh machine-path-patterns.sh; do
  expect "the $a asset is installed beside the copy" yes \
    "$(test -f "$REPO/.git/hooks/guardrails/$a" && echo yes)"
done
printf 'line one\nline two\ntoken=%s\n' "$FAKE_GHP" >"$REPO/notes.md"
git -C "$REPO" add notes.md
err="$(git -C "$REPO" commit -q -m change 2>&1)"
expect "git commit runs the installed entry and fails on the added line" "1" "$?"
expect "the commit failure names the line" "notes.md:3: secret or credential pattern: GitHub PAT" \
  "$(printf '%s\n' "$err" | head -1)"
printf 'line one\nline two\nclean\n' >"$REPO/notes.md"
git -C "$REPO" add notes.md
git -C "$REPO" commit -q -m clean 2>/dev/null
expect "a clean commit passes through the installed entry" 0 "$?"
expect "verify reports the entry ok" "ok	pre-commit-content" \
  "$(node "$INSTALL" verify --repo "$REPO" | grep 'pre-commit-content')"

# A shared install commits the copies under .githooks/guardrails/; the copies'
# own pattern text must not trip the check that ships them.
new_repo
node "$INSTALL" copy --scope shared --manager plain --entry pre-commit-content --repo "$REPO" >/dev/null
git -C "$REPO" config core.hooksPath .githooks
git -C "$REPO" add .githooks .gitattributes
git -C "$REPO" commit -q -m "add shared hooks" 2>"$WORK/shared.err"
expect "committing the shared copies passes their own check" "0|" "$?|$(cat "$WORK/shared.err")"

echo "pre-commit-content: $PASS passed, $FAIL failed"
((FAIL == 0))
