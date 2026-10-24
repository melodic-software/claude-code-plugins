#!/usr/bin/env bash
# Contract tests for the guardrails commit-msg entry (git-hooks/commit-msg-convention.sh):
# a subject off the team's tracked subject_pattern fails, a matching one and
# the autosquash forms and git's own Merge and Revert subjects pass, no tracked pattern (or a non-ERE one) enforces
# nothing, a missing resolver never blocks blind, and the plugin's vendored
# installer wires the entry so `git commit` runs it from the installed copy.
# test-scope: plugins/guardrails/git-hooks/entries.json plugins/guardrails/hooks/resolve-convention-pattern.sh plugins/guardrails/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT GIT_EDITOR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/commit-msg-convention.sh"
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

n=0
new_repo() { # [source-control.md body]
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  mkdir -p "$REPO/.claude"
  [[ -n "${1:-}" ]] && printf '%s\n' "$1" >"$REPO/.claude/source-control.md"
  return 0
}

msg() { # <repo> <message> <script> -> rc
  local repo="$1" text="$2" script="${3:-$CHECK}"
  printf '%s\n' "$text" >"$WORK/msg"
  (cd "$repo" && bash "$script" "$WORK/msg") >/dev/null 2>&1
  echo $?
}

TICKET=$'## subject_pattern\n^[A-Z]+-[0-9]+: .+'
CC=$'## subject_pattern\nConventional Commits'
PCRE=$'## subject_pattern\n^(?:feat|fix): .+'

new_repo ""
expect "no tracked pattern: any subject passes" 0 "$(msg "$REPO" "whatever subject")"
new_repo "$PCRE"
expect "a PCRE-only pattern is not enforced" 0 "$(msg "$REPO" "whatever subject")"

new_repo "$TICKET"
expect "ticket pattern: a matching subject passes" 0 "$(msg "$REPO" $'ABC-123: do the thing\n\nBody.')"
expect "ticket pattern: another subject fails" 1 "$(msg "$REPO" $'junk subject\n\nBody.')"
expect "comment lines before the subject are skipped" 0 "$(msg "$REPO" $'# template comment\nABC-9: real subject')"
expect "fixup! passes (autosquash)" 0 "$(msg "$REPO" "fixup! anything at all")"
expect "squash! passes (autosquash)" 0 "$(msg "$REPO" "squash! anything")"
expect "amend! passes (autosquash)" 0 "$(msg "$REPO" "amend! anything")"
expect "an empty message is git's to refuse" 0 "$(msg "$REPO" "")"
# With no editor (-m, -F) git keeps comment lines, and says so to the hook with
# GIT_EDITOR=:, so a subject starting with the comment character is the subject.
noedit() { # <repo> <message> -> rc
  printf '%s\n' "$2" >"$WORK/msg"
  (cd "$1" && GIT_EDITOR=: bash "$CHECK" "$WORK/msg") >/dev/null 2>&1
  echo $?
}
expect "no editor: a # subject is the subject" 1 "$(noedit "$REPO" "#123 fix thing")"
expect "no editor: a # subject is the subject even with a body" 1 "$(noedit "$REPO" $'#123 fix thing\n\nABC-1: body')"
git -C "$REPO" config commit.cleanup strip
expect "commit.cleanup=strip: # lines are comments though no editor ran" 0 "$(noedit "$REPO" $'#123 note\nABC-9: real subject')"
git -C "$REPO" config commit.cleanup verbatim
expect "commit.cleanup=verbatim: a # line is the subject though an editor ran" 1 "$(msg "$REPO" $'#123 note\nABC-9: real subject')"
git -C "$REPO" config --unset commit.cleanup
git -C "$REPO" config core.commentChar ';'
expect "core.commentChar lines are skipped" 0 "$(msg "$REPO" $'; junk comment\nABC-1: subject')"
expect "core.commentChar: a # line is the subject" 1 "$(msg "$REPO" $'# not a comment now\nABC-1: subject')"

new_repo "$CC"
expect "Conventional Commits keyword: feat: passes" 0 "$(msg "$REPO" "feat: add thing")"
expect "Conventional Commits keyword: a plain subject fails" 1 "$(msg "$REPO" "junk subject")"
expect "Conventional Commits keyword: a git-written Merge subject passes" 0 "$(msg "$REPO" "Merge branch 'x'")"
expect "Conventional Commits keyword: a git-written Revert subject passes" 0 "$(msg "$REPO" 'Revert "feat: y"')"
expect "Conventional Commits keyword: update stuff still fails" 1 "$(msg "$REPO" "update stuff")"
expect "Conventional Commits keyword: Merging without the git form still fails" 1 "$(msg "$REPO" "Mergers and acquisitions")"
expect "Conventional Commits keyword: Revert without a quote still fails" 1 "$(msg "$REPO" "Revert the thing")"
err="$( (cd "$REPO" && printf 'junk subject\n' >"$WORK/msg" && bash "$CHECK" "$WORK/msg") 2>&1 >/dev/null)"
expect "the failure names the subject and how to fix it, never a skip" "yes|no" \
  "$(grep -q 'subject: junk subject' <<<"$err" && echo yes || echo no)|$(grep -qi 'no-verify' <<<"$err" && echo yes || echo no)"

# A copy with no resolver beside it and none in a plugin tree enforces nothing.
mkdir -p "$WORK/lone"
cp "$CHECK" "$WORK/lone/commit-msg-convention.sh"
new_repo "$TICKET"
expect "no resolver anywhere: passes rather than block blind" 0 "$(msg "$REPO" "junk subject" "$WORK/lone/commit-msg-convention.sh")"

# A stub resolver beside a copy of the hook, so the resolver's exit code and
# stderr are the test's to choose (STUB_RC, STUB_ERR, STUB_OUT). Exit 1 with empty
# stderr is "no convention tracked": silent. Exit 1 with stderr, or exit 2, means
# the check did not run: one notice with the diagnostic on stderr, exit 0.
mkdir -p "$WORK/stub"
cp "$CHECK" "$WORK/stub/commit-msg-convention.sh"
cat >"$WORK/stub/resolve-convention-pattern.sh" <<'EOF'
#!/usr/bin/env bash
[[ -n "${STUB_ERR:-}" ]] && printf '%s\n' "$STUB_ERR" >&2
[[ -n "${STUB_OUT:-}" ]] && printf '%s\n' "$STUB_OUT"
exit "${STUB_RC:-0}"
EOF
new_repo ""
stub() { # <rc> <stderr> <stdout> <subject> -> sets STUB_EXIT, STUB_STDOUT, STUB_STDERR
  printf '%s\n' "$4" >"$WORK/msg"
  STUB_STDOUT="$(cd "$REPO" && STUB_RC="$1" STUB_ERR="$2" STUB_OUT="$3" bash "$WORK/stub/commit-msg-convention.sh" "$WORK/msg" 2>"$WORK/stub.err")"
  STUB_EXIT=$?
  STUB_STDERR="$(<"$WORK/stub.err")"
}
has() { grep -q -- "$1" <<<"$STUB_STDERR" && echo yes || echo no; } # <text> -> yes|no
stub 1 "" "" "junk subject"
expect "resolver exit 1, empty stderr: exit 0 and nothing printed" "0|" "$STUB_EXIT|$STUB_STDERR$STUB_STDOUT"
stub 1 "resolve-convention-pattern: broken pointer" "" "junk subject"
expect "resolver exit 1 with stderr: exit 0, one notice holding the diagnostic" "0|1|yes|yes" \
  "$STUB_EXIT|$(grep -c . <<<"$STUB_STDERR")|$(has 'did not run')|$(has 'broken pointer')"
stub 2 "resolve-convention-pattern: usage" "" "junk subject"
expect "resolver exit 2: exit 0, one notice holding the diagnostic" "0|1|yes|yes" \
  "$STUB_EXIT|$(grep -c . <<<"$STUB_STDERR")|$(has 'did not run')|$(has 'usage')"
stub 2 "" "" "junk subject"
expect "resolver exit 2, no stderr: exit 0 and the notice names the status" "0|yes" \
  "$STUB_EXIT|$(has 'exit status 2')"
stub 0 "" "^[A-Z]+-[0-9]+: .+" "junk subject"
expect "a resolved convention still rejects a non-matching subject" 1 "$STUB_EXIT"
stub 0 "" "^[A-Z]+-[0-9]+: .+" "ABC-1: fine"
expect "a resolved convention still passes a matching subject" "0|" "$STUB_EXIT|$STUB_STDERR"

expect "the sentinel marker stays on line 2 of the source" yes \
  "$(grep -q 'guardrails-commit-msg-convention' < <(sed -n 2p "$CHECK") && echo yes)"

# End to end through the plugin's vendored installer and a real commit.
new_repo "$TICKET"
git -C "$REPO" commit -q --allow-empty -m "ABC-1: seed"
status="$(node "$INSTALL" copy --scope local --entry commit-msg-convention --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"commit-msg-convention","status":"installed"}]' "$status"
expect "the resolver asset is installed beside the copy" yes \
  "$(cmp -s "$PLUGIN/hooks/resolve-convention-pattern.sh" "$REPO/.git/hooks/guardrails/resolve-convention-pattern.sh" && echo yes)"
git -C "$REPO" commit -q --allow-empty -m "junk subject" 2>/dev/null
expect "git commit runs the installed entry and refuses an off-convention subject" 1 "$?"
git -C "$REPO" commit -q --allow-empty -m "#123 fix thing" 2>/dev/null
expect "git commit -m refuses a subject that starts with #" 1 "$?"
git -C "$REPO" commit -q --allow-empty -m "ABC-2: fine subject" 2>/dev/null
expect "git commit with a matching subject succeeds" 0 "$?"
expect "verify reports the entry ok" "ok	commit-msg-convention" \
  "$(node "$INSTALL" verify --repo "$REPO" | grep 'commit-msg-convention')"

echo "commit-msg-convention: $PASS passed, $FAIL failed"
((FAIL == 0))
