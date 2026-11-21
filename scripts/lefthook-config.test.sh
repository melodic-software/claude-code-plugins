#!/usr/bin/env bash
# test-scope: lefthook.yml .claude/settings.json
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)" || exit 2
CONFIG="$REPO_ROOT/lefthook.yml"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh" || exit 2

if [[ -f "$CONFIG" ]]; then
  ok "root lefthook.yml exists"
else
  fail "root lefthook.yml missing"
  test_harness::report
fi

if grep -qx 'skip_lfs: true' "$CONFIG"; then
  ok "lefthook.yml sets skip_lfs: true"
else
  fail "lefthook.yml must set skip_lfs: true"
fi

if ! grep -q 'check-affected' "$CONFIG"; then
  ok "lefthook.yml does not run check-affected on pre-push"
else
  fail "lefthook.yml still runs check-affected on pre-push"
fi

if grep -q 'name: guardrails-remote-reference-verify' "$CONFIG" &&
  awk '
    /name: guardrails-remote-reference-verify/ { in_job = 1; next }
    in_job && /^ *- name:/ { in_job = 0 }
    in_job && /skip: true/ { found = 1 }
    END { exit !found }
  ' "$CONFIG"; then
  ok "lefthook.yml skips guardrails-remote-reference-verify on pre-push"
else
  fail "lefthook.yml must skip guardrails-remote-reference-verify on pre-push"
fi

if ! grep -q 'guardrails-remote-pre-push-content' "$CONFIG"; then
  ok "lefthook.yml does not skip guardrails-remote-pre-push-content"
else
  fail "lefthook.yml must not disable guardrails-remote-pre-push-content"
fi

if command -v jq >/dev/null 2>&1; then
  push_hooks="$(jq -r '[(.hooks.PreToolUse // [])[] | .hooks[]? | select(.if == "Bash(git push *)")] | length' "$REPO_ROOT/.claude/settings.json")"
  if [[ "$push_hooks" == "0" ]]; then
    ok ".claude/settings.json has no slow PreToolUse git-push hook"
  else
    fail ".claude/settings.json still defines a PreToolUse Bash(git push *) hook"
  fi
fi

if command -v lefthook >/dev/null 2>&1; then
  tmp="$(mktemp -d)" || exit 2
  trap 'rm -rf "$tmp"' EXIT

  if val_out="$(cd "$REPO_ROOT" && lefthook validate 2>&1)"; then
    ok "lefthook validate passes on root lefthook.yml"
  else
    fail "lefthook validate failed: $val_out"
  fi

  src="$tmp/src"
  mkdir -p "$src/plugins"
  cp -R "$REPO_ROOT/plugins/guardrails" "$src/plugins/guardrails"
  cp -R "$REPO_ROOT/plugins/code-tidying" "$src/plugins/code-tidying"
  cp -R "$REPO_ROOT/.lefthook" "$src/.lefthook"
  cp "$REPO_ROOT/lefthook-remote.yml" "$src/lefthook-remote.yml"
  git init -q -b main "$src" || exit 2
  git -C "$src" add -A || exit 2
  git -C "$src" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m src --no-verify || exit 2

  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG LEFTHOOK
    export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
    git config --global "url.file://$src.insteadOf" "https://github.com/melodic-software/claude-code-plugins"
    git config --global user.name t
    git config --global user.email t@example.invalid
    git config --global commit.gpgsign false

    work="$tmp/work"
    bare="$tmp/remote.git"
    git init -q --bare -b main "$bare" || exit 2
    git init -q -b main "$work" || exit 2
    cp "$CONFIG" "$work/lefthook.yml"
    git -C "$work" add lefthook.yml
    git -C "$work" commit -q -m "chore: seed lefthook" --no-verify
    git -C "$work" remote add origin "$bare"

    if ! install_out="$(cd "$work" && lefthook install 2>&1)"; then
      echo "FAIL_INSTALL:$install_out"
      exit 10
    fi
    dump="$(cd "$work" && lefthook dump 2>/dev/null)"
    if ! grep -q 'skip_lfs: true' <<<"$dump" ||
      ! grep -q 'name: guardrails-remote-pre-push-content' <<<"$dump" ||
      grep -q 'name: check-affected' <<<"$dump"; then
      echo "FAIL_DUMP:$dump"
      exit 11
    fi
    printf '# clean\n' >"$work/clean.md"
    git -C "$work" add clean.md
    git -C "$work" commit -q --no-verify -m "docs: clean note"
    if ! push_out="$(cd "$work" && git push origin HEAD:refs/heads/main 2>&1)"; then
      echo "FAIL_CLEAN_PUSH:$push_out"
      exit 12
    fi
    git -C "$work" remote set-head origin main >/dev/null 2>&1
    printf 'token=ghp_%s\n' "$(printf 'A%.0s' {1..36})" >"$work/secret.md"
    git -C "$work" add secret.md
    git -C "$work" commit -q --no-verify -m "docs: leak"
    rc=0
    push_out="$(cd "$work" && git push origin HEAD:refs/heads/main 2>&1)" || rc=$?
    if ((rc == 0)) || ! grep -q 'secret or credential pattern' <<<"$push_out"; then
      echo "FAIL_SECRET_PUSH:rc=$rc:$push_out"
      exit 13
    fi
  ) >"$tmp/e2e.out" 2>&1
  e2e_rc=$?
  if ((e2e_rc == 0)); then
    ok "lefthook install, dump, clean push, and secret-blocking pre-push all pass end-to-end"
  else
    fail "lefthook end-to-end failed (exit $e2e_rc): $(cat "$tmp/e2e.out")"
  fi
else
  ok "SKIP lefthook end-to-end cases (lefthook not installed)"
fi

test_harness::report
