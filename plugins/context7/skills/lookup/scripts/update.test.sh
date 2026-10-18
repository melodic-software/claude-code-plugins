#!/usr/bin/env bash
# Exit-code contract of update.sh (0 no drift, 1 drift, 2 unverifiable),
# network-free: the script runs from a copied skill tree with a PATH that holds
# only the tools it needs, plus stubs for npm, git, curl and ctx7.
# shellcheck disable=SC2016 # stub bodies are single-quoted so they expand when the stub runs
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

BIN="$TMP/bin"
mkdir -p "$BIN"
for tool in bash cat cp cut date diff dirname head mkdir mktemp rm sed tr wc; do
  real=$(command -v "$tool") || {
    echo "SKIP: $tool not installed"
    exit 0
  }
  ln -s "$real" "$BIN/$tool"
done
BASH_BIN=$(command -v bash)

stub() {
  printf '#!%s\n%s\n' "$BASH_BIN" "$2" >"$BIN/$1"
  chmod +x "$BIN/$1"
}
# npm view prints $FAKE_LATEST (fails when empty); npm install fails.
stub npm '[[ "$1" == view && -n "${FAKE_LATEST:-}" ]] && { echo "$FAKE_LATEST"; exit 0; }; exit 1'
# git ls-remote prints $FAKE_SHA for master (fails when empty).
GIT_STUB='[[ -n "${FAKE_SHA:-}" ]] && { printf "%s\trefs/heads/master\n" "$FAKE_SHA"; exit 0; }; exit 128'
stub git "$GIT_STUB"
# curl serves $FAKE_UPSTREAM/<find-docs|context7-cli>.md for the URL it is given.
stub curl 'url="" out=""
while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift ;; http*) url="$1" ;; esac; shift; done
[[ -n "${FAKE_CURL_FAIL:-}" ]] && exit 22
case "$url" in */skills/find-docs/SKILL.md) cp "$FAKE_UPSTREAM/find-docs.md" "$out" ;; */skills/context7-cli/SKILL.md) cp "$FAKE_UPSTREAM/context7-cli.md" "$out" ;; *) exit 22 ;; esac'
CTX7_STUB='echo "${FAKE_INSTALLED}"'

SKILL="$TMP/plugin/skills/lookup"
mkdir -p "$SKILL/scripts" "$SKILL/vendor/find-docs" "$SKILL/vendor/cli"
cp "$SCRIPT" "$SKILL/scripts/update.sh"
printf -- '---\nmetadata:\n  upstream-version: upstash/context7@old\n  synced: 2026-01-01\n---\n' >"$SKILL/SKILL.md"

UPSTREAM="$TMP/upstream"
mkdir -p "$UPSTREAM"
printf 'find-docs guidance\n' >"$UPSTREAM/find-docs.md"
printf 'cli guidance\n' >"$UPSTREAM/context7-cli.md"
write_baselines() {
  cp "$UPSTREAM/find-docs.md" "$SKILL/vendor/find-docs/SKILL.md"
  cp "$UPSTREAM/context7-cli.md" "$SKILL/vendor/cli/SKILL.md"
}

SHA=0123456789abcdef0123456789abcdef01234567
FAKE_LATEST=1.2.0
FAKE_INSTALLED=1.2.0
FAKE_SHA=$SHA
FAKE_CURL_FAIL=""
run() {
  out=$(env -i PATH="$BIN" FAKE_LATEST="$FAKE_LATEST" FAKE_INSTALLED="$FAKE_INSTALLED" \
    FAKE_SHA="$FAKE_SHA" FAKE_CURL_FAIL="$FAKE_CURL_FAIL" FAKE_UPSTREAM="$UPSTREAM" \
    bash "$SKILL/scripts/update.sh" "$@" 2>&1)
  code=$?
}

# 1. CLI current, both baselines match upstream.
write_baselines
stub ctx7 "$CTX7_STUB"
run
assert_eq "in sync: exit 0" 0 "$code"
assert_contains "in sync: reports no drift" "$out" "No drift detected"

# 2. ctx7 not installed, upstream unchanged: reported, not drift.
rm "$BIN/ctx7"
run
assert_eq "ctx7 not installed: exit 0" 0 "$code"
assert_contains "ctx7 not installed: reported" "$out" "ctx7 is not installed"
stub ctx7 "$CTX7_STUB"

# 3. Installed CLI behind latest.
FAKE_INSTALLED=1.1.0
run
assert_eq "CLI behind latest: exit 1" 1 "$code"
assert_contains "CLI behind latest: summary names it" "$out" "CLI version behind"
FAKE_INSTALLED=1.2.0

# 4. Upstream skill content changed.
printf 'new find-docs rule\n' >>"$UPSTREAM/find-docs.md"
run
assert_eq "upstream content changed: exit 1" 1 "$code"
assert_contains "upstream content changed: names the skill" "$out" "find-docs SKILL.md changed upstream"
write_baselines

# 5. A baseline is missing in report mode.
rm "$SKILL/vendor/cli/SKILL.md"
run
assert_eq "baseline missing: exit 1" 1 "$code"
write_baselines

# 6. Upstream unreachable.
FAKE_CURL_FAIL=1
run
assert_eq "upstream fetch fails: exit 2" 2 "$code"
FAKE_CURL_FAIL=""

FAKE_SHA=""
run
assert_eq "master unresolvable: exit 2" 2 "$code"
FAKE_SHA=$SHA

FAKE_LATEST=""
run
assert_eq "npm registry unreachable with ctx7 installed: exit 2" 2 "$code"
FAKE_LATEST=1.2.0

# 7. Drift outranks unverifiable.
FAKE_INSTALLED=1.1.0
FAKE_CURL_FAIL=1
run
assert_eq "CLI behind and upstream unreachable: exit 1" 1 "$code"
FAKE_INSTALLED=1.2.0
FAKE_CURL_FAIL=""

# 8. A prerequisite is missing.
rm "$BIN/git"
run
assert_eq "git missing: exit 2" 2 "$code"
assert_contains "git missing: names it" "$out" "Required command not found: git"
stub git "$GIT_STUB"

# 9. Usage and the requested-action failures.
run --bogus
assert_eq "unknown mode: exit 2" 2 "$code"

FAKE_INSTALLED=1.1.0
run --fix
assert_eq "--fix with a failing npm install: exit 2" 2 "$code"
FAKE_INSTALLED=1.2.0

# 10. --refresh-baseline over drift rewrites the baselines, stamps the commit, exits 0.
printf 'new cli rule\n' >>"$UPSTREAM/context7-cli.md"
run --refresh-baseline
assert_eq "--refresh-baseline over drift: exit 0" 0 "$code"
assert_eq "--refresh-baseline copies upstream" "$(cat "$UPSTREAM/context7-cli.md")" "$(cat "$SKILL/vendor/cli/SKILL.md")"
assert_contains "--refresh-baseline stamps the commit" "$(cat "$SKILL/SKILL.md")" "upstream-version: upstash/context7@$SHA"

if ((FAILED)); then
  printf '\n%d check(s) failed.\n' "$FAILED" >&2
  exit 1
fi
printf '\nAll checks passed.\n'
