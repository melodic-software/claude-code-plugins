#!/usr/bin/env bash
# test-scope: lib/git-hooks/lefthook-remote-harness.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASH_BIN="$(command -v bash)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

mkdir -p "$WORK/plugins/fake/git-hooks" "$WORK/bin"
: >"$WORK/plugins/fake/git-hooks/lefthook-remote.yml"
cat >"$WORK/plugins/fake/git-hooks/suite.sh" <<EOF
HERE="$WORK/plugins/fake/git-hooks"
. "$HERE/lefthook-remote-harness.sh"
lr_require_tools "\$1"
echo "seeded cases ran"
lr_done
EOF
ln -s "$(command -v awk)" "$WORK/bin/awk"

run() {
  env -i PATH="$WORK/bin" ${1:+LEFTHOOK_REMOTE_REQUIRE_TOOLS="$1"} "$BASH_BIN" "$WORK/plugins/fake/git-hooks/suite.sh" "$2" 2>&1
}

out="$(run "" lr-no-such-tool)"
expect "default: a missing tool skips the seeded cases and passes" \
  "0|SKIP: lr-no-such-tool not on PATH -- the seeded fake cases skipped|" \
  "$?|$(grep '^SKIP' <<<"$out")|$(grep 'seeded cases ran' <<<"$out")"

out="$(run 1 lr-no-such-tool)"
expect "LEFTHOOK_REMOTE_REQUIRE_TOOLS=1: a missing tool fails the suite, naming the tool" \
  "1|FAIL: lr-no-such-tool is on PATH for the seeded fake cases (LEFTHOOK_REMOTE_REQUIRE_TOOLS=1): want [yes] got [no]||" \
  "$?|$(grep '^FAIL' <<<"$out")|$(grep '^SKIP' <<<"$out")|$(grep 'seeded cases ran' <<<"$out")"

out="$(run 0 lr-no-such-tool)"
expect "LEFTHOOK_REMOTE_REQUIRE_TOOLS=0 skips like the default" "0|yes" "$?|$(grep -q '^SKIP: lr-no-such-tool' <<<"$out" && echo yes)"

out="$(run 1 awk)"
expect "LEFTHOOK_REMOTE_REQUIRE_TOOLS=1: a tool on PATH runs the seeded cases" "0|seeded cases ran" "$?|$(grep 'seeded cases ran' <<<"$out")"

out="$(run 1 goimports)"
expect "LEFTHOOK_REMOTE_REQUIRE_TOOLS=1: an allowed-missing tool still skips, giving its reason" \
  "0|SKIP: goimports not on PATH -- the seeded fake cases skipped (the repository pins no goimports for CI)" \
  "$?|$(grep '^SKIP' <<<"$out")"

echo "lefthook-remote-harness: $PASS passed, $FAIL failed"
((FAIL == 0))
