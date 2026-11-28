#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/update.sh"
TEST_TMPDIR="$(mktemp -d)"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

help_out=$(bash "$SCRIPT" --help 2>&1)
help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"
if [[ -n "$help_out" ]]; then
  pass "--help emits non-empty stdout"
else
  fail "--help emits non-empty stdout" "non-empty" "empty"
fi
assert_contains "--help mentions --check" "$help_out" "--check"
assert_contains "--help mentions --apply" "$help_out" "--apply"
assert_contains "--help mentions vendor" "$help_out" "vendor"

help_out_short=$(bash "$SCRIPT" -h 2>&1)
short_exit=$?
assert_exit "-h exits 0" 0 "$short_exit"
if [[ -n "$help_out_short" ]]; then
  pass "-h emits non-empty stdout"
else
  fail "-h emits non-empty stdout" "non-empty" "empty"
fi

unknown_out=$(bash "$SCRIPT" --bogus-flag 2>&1)
unknown_exit=$?
assert_exit "unknown flag exits 2" 2 "$unknown_exit"
assert_contains "unknown flag mentions expected modes" "$unknown_out" "expected"

# shellcheck source=update.sh
source "$SCRIPT" 2>/dev/null
SOURCED_TMPDIR="$TMPDIR_RUN"
trap 'rm -rf "$TEST_TMPDIR" "$SOURCED_TMPDIR"' EXIT
if declare -F local_metadata_field >/dev/null; then
  pass "source-guard: helpers exposed after source"
else
  fail "source-guard: helpers exposed after source" "function defined" "undefined"
fi

FIXTURE_SKILL="$TEST_TMPDIR/SKILL.md"
cat >"$FIXTURE_SKILL" <<'EOF'
---
name: boris
description: "test fixture"
user-invocable: true
metadata:
  author: Test Author
  upstream-version: 7.5.0
  synced: 2026-01-15
---

# Body
EOF

FRONTMATTER_FILE="$FIXTURE_SKILL"

parsed_ver=$(local_metadata_field "upstream-version")
assert_eq "parses metadata.upstream-version (nested)" "7.5.0" "$parsed_ver"

parsed_synced=$(local_metadata_field "synced")
assert_eq "parses metadata.synced (nested)" "2026-01-15" "$parsed_synced"

FIXTURE_BARE="$TEST_TMPDIR/SKILL-bare.md"
cat >"$FIXTURE_BARE" <<'EOF'
---
name: bare
description: "no metadata block"
---

# Body
EOF

FRONTMATTER_FILE="$FIXTURE_BARE"
empty_ver=$(local_metadata_field "upstream-version")
assert_eq "missing metadata block returns empty" "" "$empty_ver"

FIXTURE_MUT="$TEST_TMPDIR/SKILL-mut.md"
cat >"$FIXTURE_MUT" <<'EOF'
---
name: boris
metadata:
  upstream-version: 1.0.0
  synced: 2025-01-01
---
EOF

TMPDIR_RUN="$TEST_TMPDIR"
FRONTMATTER_FILE="$FIXTURE_MUT"
replace_metadata_field "upstream-version" "9.9.9"
replace_metadata_field "synced" "2030-12-31"

mutated=$(cat "$FIXTURE_MUT")
assert_contains "upstream-version bumped" "$mutated" "upstream-version: 9.9.9"
assert_contains "synced bumped" "$mutated" "synced: 2030-12-31"
assert_not_contains "old upstream-version removed" "$mutated" "1.0.0"
assert_not_contains "old synced removed" "$mutated" "2025-01-01"

FIXTURE_SHA="$TEST_TMPDIR/sha-fixture.txt"
echo "boris test" >"$FIXTURE_SHA"
sha_via_helper=$(sha256 "$FIXTURE_SHA" | awk '{print $1}' | tr -d '\r')
if command -v sha256sum >/dev/null 2>&1; then
  sha_direct=$(sha256sum "$FIXTURE_SHA" | awk '{print $1}' | tr -d '\r')
else
  sha_direct=$(shasum -a 256 "$FIXTURE_SHA" | awk '{print $1}' | tr -d '\r')
fi
assert_eq "sha256 helper matches direct call" "$sha_direct" "$sha_via_helper"

missing_sha=$(file_sha "$TEST_TMPDIR/does-not-exist.txt")
assert_eq "file_sha returns empty for missing path" "" "$missing_sha"

map_text=$(sed -n '/Integrate new tips/,/Update SKILL.md/p' "$SCRIPT")
for bucket in "$SCRIPT_DIR"/../reference/*.md; do
  bucket_name="$(basename "$bucket")"
  assert_contains "sync map routes $bucket_name" "$map_text" "reference/$bucket_name"
done

if grep -qE 'sections [0-9]+\+' <<<"$map_text"; then
  fail "sync map has no open-ended section range" "closed ranges" "found 'sections N+'"
else
  pass "sync map has no open-ended section range"
fi

FRONTMATTER_FILE="$FIXTURE_SKILL"
VENDOR_FILE="$TEST_TMPDIR/vendor-skill.md"
UPSTREAM_COPY="$TEST_TMPDIR/upstream-skill.md"
printf 'vendored tips\n' >"$VENDOR_FILE"
cp "$VENDOR_FILE" "$UPSTREAM_COPY"
stub_version="7.5.0"
stub_install=ok
fetch_upstream_version() { [[ -n "$stub_version" ]] && printf '%s' "$stub_version"; }
fetch_upstream_install() { [[ "$stub_install" == ok ]] && printf '%s' "$UPSTREAM_COPY"; }

out=$(run_check 2>&1)
assert_exit "version and bytes match: exit 0" 0 "$?"
assert_contains "version and bytes match: reports no drift" "$out" "No drift"

stub_version="7.6.0"
out=$(run_check 2>&1)
assert_exit "upstream version moved: exit 1" 1 "$?"
stub_version="7.5.0"

printf 'a new tip\n' >>"$UPSTREAM_COPY"
out=$(run_check 2>&1)
assert_exit "upstream bytes changed: exit 1" 1 "$?"
assert_contains "upstream bytes changed: names the drift" "$out" "vendor content drift"
cp "$VENDOR_FILE" "$UPSTREAM_COPY"

stub_version=""
out=$(run_check 2>&1)
assert_exit "version endpoint unreachable: exit 2" 2 "$?"
stub_version="7.5.0"

stub_install=fail
out=$(run_check 2>&1)
assert_exit "install endpoint unreachable: exit 2" 2 "$?"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
