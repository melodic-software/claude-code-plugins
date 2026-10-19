#!/usr/bin/env bash
# Exit-code contract of update.sh (0 no drift, 1 drift, 2 unverifiable),
# network-free: the script runs from a copied skill tree with a PATH that holds
# only the tools it needs and a curl stub that serves a local fixture.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/update.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

# A PATH with the script's tools and nothing else, so a curl or diff on this
# machine cannot leak in.
BIN="$TMP/bin"
mkdir -p "$BIN"
for tool in bash cat cp date diff dirname head mkdir mktemp rm sed tr wc; do
  real=$(command -v "$tool") || {
    echo "SKIP: $tool not installed"
    exit 0
  }
  ln -s "$real" "$BIN/$tool"
done
BASH_BIN=$(command -v bash)

# curl stub: copies $FAKE_UPSTREAM to the -o target, or fails like curl -f on a 404.
cat >"$TMP/curl" <<EOF
#!$BASH_BIN
[[ -n "\${FAKE_CURL_FAIL:-}" ]] && { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
while [[ \$# -gt 0 ]]; do
  [[ "\$1" == -o ]] && { cp "\$FAKE_UPSTREAM" "\$2"; exit \$?; }
  shift
done
exit 2
EOF
chmod +x "$TMP/curl"
ln -s "$TMP/curl" "$BIN/curl"

SKILL="$TMP/plugin/skills/sync"
mkdir -p "$SKILL/scripts" "$SKILL/vendor" "$TMP/plugin/skills/grounding"
cp "$SCRIPT" "$SKILL/scripts/update.sh"
printf -- '---\nmetadata:\n  synced: "2026-01-01"\n---\n' >"$TMP/plugin/skills/grounding/SKILL.md"

# Upstream content, and the vendored baseline: the same content plus the
# attribution comment and the blank line after it, which upstream never carries.
UPSTREAM="$TMP/upstream.md"
printf -- '---\nname: dometrain-grounding\n---\n\nGround the approach in the course.\n' >"$UPSTREAM"
write_baseline() {
  {
    printf -- '---\nname: dometrain-grounding\n---\n\n'
    printf '<!-- Vendored from https://github.com/Dometrain/mcp, MIT licensed. -->\n\n'
    printf 'Ground the approach in the course.\n'
  } >"$SKILL/vendor/SKILL.md"
}

run() {
  out=$(env -i PATH="$BIN" FAKE_UPSTREAM="$UPSTREAM" FAKE_CURL_FAIL="${FAKE_CURL_FAIL:-}" \
    bash "$SKILL/scripts/update.sh" "$@" 2>&1)
  code=$?
}

# 1. Upstream matches the baseline once the attribution is stripped.
write_baseline
run
assert_eq "baseline matches upstream: exit 0" 0 "$code"
assert_contains "baseline matches upstream: reports no drift" "$out" "No drift detected"
run report
assert_eq "explicit report mode: exit 0" 0 "$code"

# 2. Upstream changed.
printf 'A new paragraph upstream.\n' >>"$UPSTREAM"
run
assert_eq "upstream changed: exit 1" 1 "$code"
assert_contains "upstream changed: shows the new line" "$out" "+A new paragraph upstream."

# 3. Baseline missing in report mode is drift.
rm "$SKILL/vendor/SKILL.md"
run
assert_eq "baseline missing: exit 1" 1 "$code"
assert_contains "baseline missing: says so" "$out" "No baseline"

# 4. The fetch fails.
write_baseline
FAKE_CURL_FAIL=1 run
assert_eq "fetch fails: exit 2" 2 "$code"

# 5. A prerequisite is missing.
rm "$BIN/diff"
run
assert_eq "diff missing: exit 2" 2 "$code"
assert_contains "diff missing: names it" "$out" "Required command not found: diff"
ln -s "$(command -v diff)" "$BIN/diff"

# 6. Unknown mode.
run --bogus
assert_eq "unknown mode: exit 2" 2 "$code"

# 7. --refresh-baseline over drift rewrites the baseline and exits 0.
run --refresh-baseline
assert_eq "--refresh-baseline over drift: exit 0" 0 "$code"
assert_eq "--refresh-baseline copies upstream" "$(cat "$UPSTREAM")" "$(cat "$SKILL/vendor/SKILL.md")"
run
assert_eq "after refresh: exit 0" 0 "$code"

if ((FAILED)); then
  printf '\n%d check(s) failed.\n' "$FAILED" >&2
  exit 1
fi
printf '\nAll checks passed.\n'
