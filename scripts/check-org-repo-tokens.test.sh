#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass only prints and counts, so `A && pass || bad` cannot run both
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=test-git-helpers.sh
. "$SCRIPT_DIR/test-git-helpers.sh" || exit 2

SUT="$SCRIPT_DIR/check-org-repo-tokens.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

R="$TMP/repo"
mkdir -p "$R/plugins/p/skills/s" "$R/plugins/p/evals/e" "$R/plugins/p/.claude-plugin"
git_init_test_repo "$R" || exit 2
ALLOW="$TMP/allow.tsv"
: >"$ALLOW"

put() {
  mkdir -p "$(dirname "$R/$1")"
  printf '%s\n' "$2" >"$R/$1"
  git_test_config "$R" add "$1"
}
run() {
  OUT=$(ORG_REPO_TOKENS_ROOT="$R" ORG_REPO_TOKENS_ALLOW="$ALLOW" bash "$SUT" 2>"$TMP/err")
  RC=$?
  ERR=$(cat "$TMP/err")
  if [[ "$RC" == "$1" ]]; then pass "$2 (exit $RC)"; else bad "$2" "want exit $1, got $RC; stdout: $OUT; stderr: $ERR"; fi
}

put plugins/p/skills/s/SKILL.md 'Nothing organization-specific here.'
run 0 "a clean tree"
[[ "$OUT" == *"no unexcused"* && -z "$ERR" ]] && pass "clean: statement on stdout only" || bad "clean output" "$OUT / $ERR"

put plugins/p/skills/s/SKILL.md 'Read [the doc](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/x.md) and file at https://github.com/melodic-software/claude-code-plugins/issues/1.
/plugin marketplace add melodic-software/claude-code-plugins
Pointer: melodic-software/standards owns the rule.
Basis: melodic-software/ci-workflows reviewed.
As of 2026-11-19 melodic-software/dotfiles holds it.'
put plugins/p/CHANGELOG.md 'melodic-software/standards'
put plugins/p/.claude-plugin/plugin.json '"repository": "https://github.com/melodic-software/claude-code-plugins"'
put plugins/p/evals/e/case.md 'gh issue create -R melodic-software/other'
put plugins/p/skills/s/x.test.sh 'melodic-software/other'
put plugins/p/skills/s/test_x.py 'melodic-software/other'
run 0 "citation shapes and excluded files pass"

put plugins/p/skills/s/run.md 'gh issue create -R melodic-software/standards'
run 1 "a repository the skill acts on fails"
[[ "$ERR" == *"plugins/p/skills/s/run.md: 1 occurrence(s) of melodic-software/standards (allowed 0), line(s) 1"* ]] && pass "finding names path, token and line" || bad "finding text" "$ERR"
[[ -z "$OUT" ]] && pass "findings stay off stdout" || bad "stdout on findings" "$OUT"

put plugins/p/skills/s/raw.md 'curl https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/x.md'
put plugins/p/skills/s/pages.md 'see https://melodic-software.github.io/claude-code-plugins/x'
run 1 "an organization pages URL fails"
[[ "$ERR" == *"pages.md: 1 occurrence(s) of melodic-software.github.io/claude-code-plugins"* ]] && pass "the pages token is named" || bad "pages token" "$ERR"
git_test_config "$R" rm -q --cached plugins/p/skills/s/pages.md
printf 'plugins/p/skills/s/run.md\tmelodic-software/standards\t1\tissue target\n' >"$ALLOW"
run 1 "a raw fetch of the own repository is not a citation"
[[ "$ERR" == *"raw.md: 1 occurrence(s) of melodic-software/claude-code-plugins"* && "$ERR" != *"run.md"* ]] && pass "the allowed entry covers run.md only" || bad "allow scoping" "$ERR"

printf 'plugins/p/skills/s/raw.md\tmelodic-software/claude-code-plugins\t1\traw doc\n' >>"$ALLOW"
run 0 "counted entries pass"

put plugins/p/skills/s/run.md 'gh issue create -R melodic-software/standards
gh issue list -R melodic-software/standards.git'
run 1 "a second occurrence above the count fails"

printf 'plugins/p/skills/s/run.md\tmelodic-software/standards\t3\tissue target\nplugins/p/skills/s/raw.md\tmelodic-software/claude-code-plugins\t1\traw doc\n' >"$ALLOW"
run 0 "an entry above the count passes"
[[ "$OUT" == *"notice: plugins/p/skills/s/run.md allows 3 of melodic-software/standards, now 2"* ]] && pass "and asks to lower it" || bad "lower notice" "$OUT"

printf 'plugins/p/skills/s/run.md\tmelodic-software/standards\tmany\n' >"$ALLOW"
run 2 "a malformed allow entry is a usage error"
ORG_REPO_TOKENS_ROOT="$R" ORG_REPO_TOKENS_ALLOW="$TMP/missing.tsv" bash "$SUT" >/dev/null 2>&1
[[ $? == 2 ]] && pass "a missing allow file exits 2" || bad "missing allow file"
ORG_REPO_TOKENS_ROOT="$TMP" ORG_REPO_TOKENS_ALLOW="$ALLOW" bash "$SUT" >/dev/null 2>&1
[[ $? == 2 ]] && pass "a root outside a work tree exits 2" || bad "non-repo root"

test_harness::report
