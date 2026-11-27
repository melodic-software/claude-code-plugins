#!/usr/bin/env bash
# test-scope: scripts/pre-push-branch-checks.sh scripts/check-changelog-fragments.sh scripts/check-changelog-parity.sh
# test-scope: scripts/sync-plugin-options-docs.py scripts/validate-plugin-contracts.mjs scripts/generate-marketplace.mjs
# test-scope: scripts/generate-catalog.mjs scripts/generate-cheatsheet.mjs scripts/cheatsheet-config.mjs scripts/lib/*
# test-scope: lefthook.yml
set -uo pipefail

unset GITHUB_EVENT_NAME MERGE_GROUP_BASE_SHA CHANGELOG_PR_HEAD CHANGELOG_HEAD_REF \
  CHANGELOG_PR_AUTHOR GITHUB_REPOSITORY VALIDATE_CONTRACTS_BASE_REF CHECK_DATA_ROOT CHANGELOG_PARITY_ROOT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
HOOK="$SELF_DIR/pre-push-branch-checks.sh"
. "$SELF_DIR/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

BUDGET_DESK_MS=3000
REFERENCE_DESK_MS=100
ROUNDS=3
ZERO=0000000000000000000000000000000000000000
f=""
REAL_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD)" || exit 2
OBJECTS="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir)/objects" || exit 2

now_ms() { python3 -c 'import time; print(time.monotonic_ns() // 1000000)'; }

reference_files() {
  local i
  REFERENCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-reference.XXXXXX")" || return 1
  for ((i = 0; i < 400; i++)); do
    printf '%04d %.0s' "$i" {1..800} >"$REFERENCE_DIR/f$i.md"
  done
}

reference() {
  local js='const fs = require("fs"), c = require("crypto"), d = process.argv[1]; let n = 0;
    for (let r = 0; r < 12; r++) for (const f of fs.readdirSync(d)) n += c.createHash("sha256").update(fs.readFileSync(`${d}/${f}`)).digest()[0];
    JSON.parse(JSON.stringify(Array.from({ length: 40000 }, (_, i) => ({ i, s: String(i) }))));'
  local py='import hashlib, os, sys; d = sys.argv[1]; sum(hashlib.sha256(open(os.path.join(d, f), "rb").read()).digest()[0] for _ in range(12) for f in os.listdir(d))'
  local pids=() p rc=0
  for p in 1 2 3 4; do
    node -e "$js" "$REFERENCE_DIR" &
    pids+=($!)
  done
  python3 -c "$py" "$REFERENCE_DIR" &
  pids+=($!)
  for p in "${pids[@]}"; do wait "$p" || rc=1; done
  return "$rc"
}

median() { printf '%s\n' "$@" | sort -n | sed -n "$((($# + 1) / 2))p"; }

push_line() { printf 'refs/heads/topic %s refs/heads/topic %s\n' "$(git -C "$f" rev-parse HEAD)" "$ZERO"; }

hook_once() { (cd "$f" && push_line | bash scripts/pre-push-branch-checks.sh origin >/dev/null 2>&1); }

measure() {
  local r t0 t1 t2 hooks=() refs=() ref
  hook_once
  reference || return 2
  for ((r = 0; r < ROUNDS; r++)); do
    t0="$(now_ms)"
    hook_once
    t1="$(now_ms)"
    reference || return 2
    t2="$(now_ms)"
    hooks+=($((t1 - t0)))
    refs+=($((t2 - t1)))
  done
  ref="$(median "${refs[@]}")"
  printf '%s %s %s\n' "$(median "${hooks[@]}")" "$ref" $((BUDGET_DESK_MS * ref / REFERENCE_DESK_MS))
}

reference_files || {
  fail "the reference workload's files could not be written"
  test_harness::report
}
trap 'rm -rf "${REFERENCE_DIR:?}"' EXIT
fixture_tree::build f --git --label prepush-timing || {
  fail "the snapshot fixture of HEAD could not be built"
  test_harness::report
}
printf '%s\n' "$OBJECTS" >"$f/.git/objects/info/alternates"
git_test_config "$f" update-ref refs/heads/main "$REAL_HEAD" &&
  git_test_config "$f" symbolic-ref HEAD refs/heads/main &&
  git_test_config "$f" read-tree -u --reset HEAD || {
  fail "the fixture could not check out HEAD"
  test_harness::report
}
cp "$HOOK" "$f/scripts/pre-push-branch-checks.sh"
git_test_config "$f" add -A && git_test_config "$f" commit -q --allow-empty -m hook &&
  git_test_config "$f" update-ref refs/remotes/origin/main HEAD &&
  git_test_config "$f" checkout -q -B topic main

read -r hook_ms ref_ms budget_ms < <(measure) || true
if [[ -z "${budget_ms:-}" ]]; then
  fail "the reference workload could not run, so the hook was not timed"
elif ((hook_ms <= budget_ms)); then
  ok "the pre-push hook ran in ${hook_ms} ms, within its ${budget_ms} ms budget (reference ${ref_ms} ms, desk ${REFERENCE_DESK_MS} ms)"
else
  fail "the pre-push hook took ${hook_ms} ms, over its ${budget_ms} ms budget (reference ${ref_ms} ms, desk ${REFERENCE_DESK_MS} ms): make the slow check fit or move it to CI (owner-decisions L413)"
fi

case "$(uname -s 2>/dev/null)" in
MINGW* | MSYS* | CYGWIN*) test_harness::report ;;
*) ;;
esac

slow="$(mktemp "$f/.git/slow.XXXXXX")"
original="$(mktemp "$f/.git/original.XXXXXX")"
cat "$f/scripts/check-changelog-parity.sh" >"$original"
awk -v b="${budget_ms:-$BUDGET_DESK_MS}" 'NR == 2 { printf "sleep %.1f\n", (b > 3500 ? b : 3500) / 4000 + 0.3 } { print }' \
  "$original" >"$slow"
cat "$slow" >"$f/scripts/check-changelog-parity.sh"
git_test_config "$f" commit -qam slow-check
read -r slow_ms _ slow_budget_ms < <(measure) || true
if [[ -n "${slow_budget_ms:-}" ]] && ((slow_ms > slow_budget_ms)); then
  ok "a check slowed past the budget fails the guard (${slow_ms} ms over ${slow_budget_ms} ms)"
else
  fail "a check slowed past the budget did not fail the guard: ${slow_ms:-?} ms against ${slow_budget_ms:-?} ms"
fi
out="$(cd "$f" && push_line | bash scripts/pre-push-branch-checks.sh origin 2>&1)"
if [[ "$out" == *"over the 3 s hook budget"* ]]; then
  ok "a push whose checks run past 3 s warns that it is over the hook budget"
else
  fail "a push over 3 s did not warn: $out"
fi
if ((${hook_ms:-3000} < 2500)); then
  cat "$original" >"$f/scripts/check-changelog-parity.sh"
  git_test_config "$f" commit -qam fast-check
  out="$(cd "$f" && push_line | bash scripts/pre-push-branch-checks.sh origin 2>&1)"
  if [[ "$out" != *"over the 3 s hook budget"* ]]; then
    ok "a push under 3 s prints no budget warning"
  else
    fail "a push under 3 s warned: $out"
  fi
fi

test_harness::report
