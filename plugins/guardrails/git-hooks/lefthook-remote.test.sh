#!/usr/bin/env bash
# test-scope: plugins/guardrails/git-hooks/lefthook-remote.yml plugins/guardrails/git-hooks/entries.json plugins/guardrails/lib/git-hooks/install.mjs plugins/guardrails/git-hooks/commit-msg-convention.sh plugins/guardrails/git-hooks/pre-commit-content.sh plugins/guardrails/git-hooks/reference-verify.sh plugins/guardrails/git-hooks/pre-push-content.sh plugins/guardrails/git-hooks/content-scan.sh plugins/guardrails/hooks/block-no-verify.sh .lefthook/*/guardrails-* .lefthook/remote-entry.sh lefthook-remote.yml plugins/*/git-hooks/lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done

mkdir -p "$REPO/docs/conventions"
printf "subject_pattern: '^[A-Z]+-[0-9]+: .+'\n" >"$REPO/docs/conventions/source-control.yaml"
git -C "$REPO" add -A
lr_commit "feat: off convention"
lr_expect_block "commit-msg: an off-convention subject blocks" guardrails-remote-commit-msg-convention .
lr_commit "ABC-1: seed"
lr_expect_pass "commit-msg: a subject on the consumer's pattern passes"
git -C "$REPO" push -q origin main >/dev/null 2>&1
git -C "$REPO" remote set-head origin main >/dev/null

printf 'a\ntoken=ghp_%s\n' "$(printf 'A%.0s' {1..36})" >"$REPO/notes.md"
git -C "$REPO" add notes.md
lr_commit "ABC-2: notes"
lr_expect_block "pre-commit: a staged token blocks, naming the consumer's line" guardrails-remote-pre-commit-content \
  'notes\.md:2: secret or credential pattern'

guard() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' |
    CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED=true bash "$PLUGIN/hooks/block-no-verify.sh" >/dev/null 2>&1
  echo "$?"
}
if command -v jq >/dev/null 2>&1; then
  expect "block-no-verify: the commit retried after the skip is allowed" 0 "$(guard "git -C $REPO commit -m 'ABC-2: notes'")"
  expect "block-no-verify: writing the skip through the shell is allowed" 0 \
    "$(guard "printf 'pre-commit:\n  jobs:\n    - name: guardrails-remote-pre-commit-content\n      skip: true\n' >$REPO/lefthook-local.yml")"
  expect "block-no-verify: --no-verify is still blocked" 2 "$(guard "git -C $REPO commit --no-verify -m 'ABC-2: notes'")"
  expect "block-no-verify: LEFTHOOK=0 is still blocked" 2 "$(guard "LEFTHOOK=0 git -C $REPO commit -m 'ABC-2: notes'")"
fi
LR_SKIP_MSG="ABC-9: skipped" lr_skip pre-commit guardrails-remote-pre-commit-content commit
git -C "$REPO" reset -q --soft HEAD~1
git -C "$REPO" rm -q --cached notes.md
rm "$REPO/notes.md"
printf 'b\ntoken=ghp_%s\n' "$(printf 'C%.0s' {1..36})" >"$REPO/again.md"
git -C "$REPO" add again.md
lr_commit "ABC-2: again"
lr_expect_block "pre-commit: with the skip removed, the job blocks again" guardrails-remote-pre-commit-content 'again\.md:2:'
git -C "$REPO" rm -q --cached again.md
rm "$REPO/again.md"

if command -v jq >/dev/null 2>&1; then
  mkdir -p "$REPO/plugins/alpha/.claude-plugin" "$REPO/plugins/alpha/skills/setup"
  printf '{"name":"alpha","version":"0.1.0"}\n' >"$REPO/plugins/alpha/.claude-plugin/plugin.json"
  : >"$REPO/plugins/alpha/skills/setup/SKILL.md"
  git -C "$REPO" add plugins
  lr_commit "ABC-3: plugin"
  git -C "$REPO" push -q origin main >/dev/null 2>&1
  # shellcheck disable=SC2016 # the backticks are Markdown, not a substitution
  printf 'Run `/alpha:missing`.\n' >"$REPO/NOTES.md"
  git -C "$REPO" add NOTES.md
  lr_commit "ABC-4: cite"
  lr_push
  lr_expect_block "pre-push: a pushed unresolved skill reference blocks, from the refs on stdin" \
    guardrails-remote-reference-verify 'NOTES\.md:1: skill-reference-verify'
  git -C "$REPO" config checks.guardrails.reference-verify.declined true
  lr_push
  lr_expect_pass "pre-push: with the entry declined, the same push passes"
  git -C "$REPO" config --unset checks.guardrails.reference-verify.declined
  # shellcheck disable=SC2016 # the backticks are Markdown, not a substitution
  printf 'Run `/alpha:gone`.\n' >"$REPO/LATER.md"
  printf 'b\ntoken=ghp_%s\n' "$(printf 'B%.0s' {1..36})" >"$REPO/later.md"
  git -C "$REPO" add LATER.md later.md
  git -C "$REPO" commit -q --no-verify -m "ABC-5: later" >/dev/null 2>&1
  git -C "$REPO" switch -q -c side-content
  err="$(git -C "$REPO" push origin main 2>&1)"
  expect "pre-push: both stdin jobs block in one push, each from the refs on stdin" "1|yes|yes" \
    "$?|$(grep -q 'LATER.md:1: skill-reference-verify' <<<"$err" && echo yes)|$(grep -q 'later.md:2: secret or credential pattern' <<<"$err" && echo yes)"
  git -C "$REPO" switch -q main
elif [[ "${LEFTHOOK_REMOTE_REQUIRE:-${GUARDRAILS_REQUIRE_LEFTHOOK:-}}" == 1 ]]; then
  expect "jq is on PATH for the pre-push and guard cases" yes no
else
  echo "SKIP: jq not on PATH -- the pre-push and guard cases skipped"
fi

CACHED="$FETCHED/plugins/guardrails/git-hooks/lefthook-remote.yml"
expect "the remote is fetched into claude-code-plugins-main" yes "$([[ -f "$CACHED" ]] && echo yes)"
echo "# newer" >>"$SRC/plugins/guardrails/git-hooks/lefthook-remote.yml"
git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -am newer --no-verify
(cd "$REPO" && lefthook install >/dev/null 2>&1)
expect "a new commit on main reaches the consumer on lefthook install" yes \
  "$(grep -q '# newer' "$CACHED" && echo yes || echo no)"

for f in "$TOP"/plugins/*/git-hooks/lefthook-remote.yml; do
  rel="${f#"$TOP"/}"
  mkdir -p "$SRC/${rel%/*}"
  cp "$f" "$SRC/$rel"
done
git -C "$SRC" add -A
git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -m all --no-verify
(cd "$REPO" && lefthook install >/dev/null 2>&1)
dump="$(cd "$REPO" && lefthook dump 2>/dev/null)"
want="" got=""
for f in "$TOP"/plugins/*/git-hooks/lefthook-remote.yml; do
  while read -r job; do
    want+="$job "
    grep -q "name: $job\$" <<<"$dump" && got+="$job "
  done < <(sed -n 's/^ *- name: //p' "$f")
done
expect "the root aggregate merges every plugin's remote jobs into the consumer's config" "$want" "$got"

lr_done
