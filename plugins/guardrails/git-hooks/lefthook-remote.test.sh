#!/usr/bin/env bash
# test-scope: plugins/guardrails/git-hooks/lefthook-remote.yml plugins/guardrails/git-hooks/entries.json plugins/guardrails/lib/git-hooks/install.mjs plugins/guardrails/git-hooks/commit-msg-convention.sh plugins/guardrails/git-hooks/pre-commit-content.sh plugins/guardrails/git-hooks/pre-push-content.sh plugins/guardrails/git-hooks/content-scan.sh plugins/guardrails/hooks/block-no-verify.sh .lefthook/*/guardrails-* .lefthook/remote-entry.sh lefthook-remote.yml plugins/*/git-hooks/lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

LR_NO_SKIP_JOBS="guardrails-remote-pre-commit-content guardrails-remote-pre-push-content"
lr_static
lr_e2e_start || lr_done

no_skip() {
  grep -q -e 'skip: true' -e 'lefthook-local\.yml' -e "^$2 failed" -e "- name: $2\$" <<<"$1" || echo yes
}

mkdir -p "$REPO/docs/conventions"
printf "subject_pattern: '^[A-Z]+-[0-9]+: .+'\n" >"$REPO/docs/conventions/source-control.yaml"
git -C "$REPO" add -A
lr_commit "feat: off convention"
lr_expect_block "commit-msg: an off-convention subject blocks" guardrails-remote-commit-msg-convention .

guard() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' |
    CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED=true bash "$PLUGIN/hooks/block-no-verify.sh" >/dev/null 2>&1
  echo "$?"
}
if command -v jq >/dev/null 2>&1; then
  expect "block-no-verify: the commit retried after the skip is allowed" 0 "$(guard "git -C $REPO commit -m 'feat: off convention'")"
  expect "block-no-verify: writing the skip through the shell is allowed" 0 \
    "$(guard "printf 'commit-msg:\n  jobs:\n    - name: guardrails-remote-commit-msg-convention\n      skip: true\n' >$REPO/lefthook-local.yml")"
  expect "block-no-verify: --no-verify is still blocked" 2 "$(guard "git -C $REPO commit --no-verify -m 'feat: off convention'")"
  expect "block-no-verify: LEFTHOOK=0 is still blocked" 2 "$(guard "LEFTHOOK=0 git -C $REPO commit -m 'feat: off convention'")"
fi
LR_SKIP_MSG="feat: off convention" lr_skip commit-msg guardrails-remote-commit-msg-convention commit
git -C "$REPO" reset -q --soft HEAD~1
lr_commit "feat: off convention"
lr_expect_block "commit-msg: with the skip removed, the job blocks again" guardrails-remote-commit-msg-convention .
lr_commit "ABC-1: seed"
lr_expect_pass "commit-msg: a subject on the consumer's pattern passes"
git -C "$REPO" push -q origin main >/dev/null 2>&1
git -C "$REPO" remote set-head origin main >/dev/null

printf 'a\ntoken=ghp_%s\n' "$(printf 'A%.0s' {1..36})" >"$REPO/notes.md"
git -C "$REPO" add notes.md
lr_commit "ABC-2: notes"
expect "pre-commit: a staged token blocks, naming the consumer's line and no per-clone skip" "1|yes|yes" \
  "$((LR_RC != 0))|$(grep -q 'notes\.md:2: secret or credential pattern' <<<"$LR_ERR" && echo yes)|$(no_skip "$LR_ERR" guardrails-remote-pre-commit-content)"
git -C "$REPO" rm -q --cached notes.md
rm "$REPO/notes.md"

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
  lr_expect_pass "pre-push: an unresolved skill reference does not block, since reference-verify left pre-push"
  printf 'b\ntoken=ghp_%s\n' "$(printf 'B%.0s' {1..36})" >"$REPO/later.md"
  git -C "$REPO" add later.md
  git -C "$REPO" commit -q --no-verify -m "ABC-5: later" >/dev/null 2>&1
  lr_push
  expect "pre-push: a pushed token blocks from the refs on stdin, naming no per-clone skip" "1|yes|yes" \
    "$((LR_RC != 0))|$(grep -q 'later\.md:2: secret or credential pattern' <<<"$LR_ERR" && echo yes)|$(no_skip "$LR_ERR" guardrails-remote-pre-push-content)"
elif [[ "${LEFTHOOK_REMOTE_REQUIRE_TOOLS:-}" == 1 || "${LEFTHOOK_REMOTE_REQUIRE:-${GUARDRAILS_REQUIRE_LEFTHOOK:-}}" == 1 ]]; then
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
