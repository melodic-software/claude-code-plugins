#!/usr/bin/env bash
# Contract test for check-drift.sh pin-file paths.
#
# check-drift.sh HEADs upstream URLs. This suite never runs it. It asserts the
# load-bearing relative paths after the references/ to reference/ spoke rename
# and that the extracted pin() helper can read a fixture table.
#
# Assertion helpers are duplicated per plugin on purpose:
# docs/conventions/shell-test-helpers/README.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/check-drift.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

assert_file() {
  local label="$1" path="$2"
  if [[ -f "${path}" ]]; then
    pass "${label}"
  else
    fail "${label} (missing ${path})"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -- "${needle}" <<<"${haystack}"; then
    pass "${label}"
  else
    fail "${label} (does not contain: ${needle})"
  fi
}

assert_lacks() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -- "${needle}" <<<"${haystack}"; then
    fail "${label} (unexpectedly contains: ${needle})"
  else
    pass "${label}"
  fi
}

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [[ "${got}" == "${want}" ]]; then
    pass "${label}"
  else
    fail "${label} (want ${want}, got ${got})"
  fi
}

assert_file "check-drift.sh is present" "${SUT}"

src="$(cat "${SUT}")"
assert_contains "versions pin path is reference/" "${src}" \
  'VERSIONS_MD="${SCRIPT_DIR}/../reference/versions.md"'
assert_contains "sources pin path is reference/" "${src}" \
  'SOURCES_MD="${SCRIPT_DIR}/../reference/sources.md"'
assert_lacks "no leftover references/ pin path" "${src}" "../references/"

assert_file "shipped versions.md sits next to the script" \
  "${SCRIPT_DIR}/../reference/versions.md"
assert_file "shipped sources.md sits next to the script" \
  "${SCRIPT_DIR}/../reference/sources.md"

# Extract pin() from the SUT and run it against a fixture so a parser
# regression fails here instead of as a silent skip in the live probe.
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

awk '
  /^pin\(\)/ { keep = 1 }
  keep { print }
  keep && /^}$/ { exit }
' "${SUT}" >"${TMP}/pin.sh"

cat >"${TMP}/versions.md" <<'EOF'
## Kindle for PC

| Field | Value |
|---|---|
| Installer URL | `https://example.test/kindle.exe` |
| SHA256 | `abc123` |

## Other

| Field | Value |
|---|---|
| Installer URL | `https://example.test/other.exe` |
EOF

# shellcheck source=/dev/null
source "${TMP}/pin.sh"
got="$(pin "${TMP}/versions.md" "Kindle for PC" "Installer URL")"
assert_eq "pin() reads the labeled row in the named section" \
  "https://example.test/kindle.exe" "${got}"

got_sha="$(pin "${TMP}/versions.md" "Kindle for PC" "SHA256")"
assert_eq "pin() reads a second label in the same section" \
  "abc123" "${got_sha}"

# pin() calls exit, so the miss case must run in a subshell.
if ( pin "${TMP}/versions.md" "Kindle for PC" "Missing row" >/dev/null 2>"${TMP}/pin.err" ); then
  fail "pin() exits non-zero when the label is absent"
else
  pass "pin() exits non-zero when the label is absent"
fi
assert_contains "missing-pin error names the file" "$(cat "${TMP}/pin.err")" \
  "${TMP}/versions.md"

if ((fails > 0)); then
  printf 'FAIL: %d assertion(s) failed\n' "${fails}" >&2
  exit 1
fi
printf 'PASS\n'
exit 0
