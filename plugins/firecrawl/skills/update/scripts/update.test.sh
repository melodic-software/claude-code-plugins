#!/usr/bin/env bash
# Self-contained regression tests for update.sh (no external test lib — ships
# with the plugin; network-free: exercises help, arg handling, and the sourced
# helper functions against local fixtures only).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/update.sh"
TEST_TMPDIR="$(mktemp -d)"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

# --- 1. --help contract --------------------------------------------------------

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
assert_contains "--help mentions upstream.md" "$help_out" "upstream.md"

help_out_short=$(bash "$SCRIPT" -h 2>&1)
short_exit=$?
assert_exit "-h exits 0" 0 "$short_exit"
assert_contains "-h mentions --check" "$help_out_short" "--check"

# --- 2. Unknown flag handling ----------------------------------------------------

unknown_out=$(bash "$SCRIPT" --bogus-flag 2>&1)
unknown_exit=$?
assert_exit "unknown flag exits 2" 2 "$unknown_exit"
assert_contains "unknown flag mentions expected modes" "$unknown_out" "expected"

# --- 3. Source-guard: helpers callable when sourced ------------------------------

# Sourcing installs the script's own EXIT trap (cleanup of its TMPDIR_RUN); the
# trap set after it replaces that one and removes both directories.
# shellcheck source=update.sh
source "$SCRIPT" 2>/dev/null
SOURCED_TMPDIR="$TMPDIR_RUN"
trap 'rm -rf "$TEST_TMPDIR" "$SOURCED_TMPDIR"' EXIT
if declare -F recorded_field >/dev/null; then
  pass "source-guard: helpers exposed after source"
else
  fail "source-guard: helpers exposed after source" "function defined" "undefined"
fi

# --- 4. recorded_field parses upstream.md fixture ----------------------------------

FIXTURE_UP="$TEST_TMPDIR/upstream.md"
cat >"$FIXTURE_UP" <<'EOF'
# Firecrawl skill upstream sync state

- Last sync: 2026-05-22
- Upstream SHA256: abc123def456
- CLI version at sync: 1.18.0
- Previous CLI version (rollback target): 1.16.0
EOF

UPSTREAM_MD="$FIXTURE_UP"
parsed_sha=$(recorded_upstream_sha)
assert_eq "parses recorded Upstream SHA256" "abc123def456" "$parsed_sha"
parsed_ver=$(recorded_cli_version)
assert_eq "parses recorded CLI version" "1.18.0" "$parsed_ver"

# Missing file yields empty, not an error.
UPSTREAM_MD="$TEST_TMPDIR/does-not-exist.md"
missing=$(recorded_upstream_sha)
assert_eq "missing upstream.md returns empty" "" "$missing"

# --- 5. rewrite_upstream_md writes the full record ----------------------------------

UPSTREAM_MD="$TEST_TMPDIR/upstream-out.md"
rewrite_upstream_md "deadbeef" "2.0.0" "1.18.0"
written=$(cat "$UPSTREAM_MD")
assert_contains "record has SHA" "$written" "Upstream SHA256: deadbeef"
assert_contains "record has version" "$written" "CLI version at sync: 2.0.0"
assert_contains "record has rollback target" "$written" "rollback target): 1.18.0"

# --- 6. sha256 helper matches a direct call ------------------------------------------

FIXTURE_SHA="$TEST_TMPDIR/sha-fixture.txt"
echo "firecrawl test" >"$FIXTURE_SHA"
sha_via_helper=$(sha256 "$FIXTURE_SHA" | awk '{print $1}' | tr -d '\r')
if command -v sha256sum >/dev/null 2>&1; then
  sha_direct=$(sha256sum "$FIXTURE_SHA" | awk '{print $1}' | tr -d '\r')
else
  sha_direct=$(shasum -a 256 "$FIXTURE_SHA" | awk '{print $1}' | tr -d '\r')
fi
assert_eq "sha256 helper matches direct call" "$sha_direct" "$sha_via_helper"

# --- 7. Never-synced placeholders read as empty -------------------------------------
# The placeholder lines are the ones upstream.md carried before its first sync,
# which the report used to print as `last sync:  recorded)`.

FIXTURE_NEVER="$TEST_TMPDIR/upstream-never.md"
cat >"$FIXTURE_NEVER" <<'EOF'
- Last sync: never
- Upstream SHA256: (none recorded)
- CLI version at sync: (none recorded)
EOF
UPSTREAM_MD="$FIXTURE_NEVER"
assert_eq "placeholder SHA reads as empty" "" "$(recorded_upstream_sha)"
assert_eq "placeholder CLI version reads as empty" "" "$(recorded_cli_version)"
assert_eq "placeholder sync date reads as empty" "" "$(recorded_sync_date)"
UPSTREAM_MD="$FIXTURE_UP"
assert_eq "parses recorded Last sync" "2026-05-22" "$(recorded_sync_date)"

# --- 8. run_check exit-code contract (0 no drift, 1 drift, 2 unverifiable) ----------
# Network helpers are stubbed; the recorded state is the section 4 fixture.

stub_current="1.18.0"
stub_latest="1.18.0"
stub_sha="abc123def456"
current_cli_version() { printf '%s' "$stub_current"; }
latest_cli_version() { [[ -n "$stub_latest" ]] && printf '%s' "$stub_latest"; }
fetch_upstream_sha() { [[ -n "$stub_sha" ]] && printf '%s' "$stub_sha"; }

out=$(run_check 2>&1)
assert_exit "in sync: exit 0" 0 "$?"
assert_contains "in sync: reports no drift" "$out" "No drift"
assert_contains "report prints the recorded sync date" "$out" "last sync:  2026-05-22"
assert_contains "report prints the recorded SHA256" "$out" "recorded SHA256: abc123def456"

stub_current=""
out=$(run_check 2>&1)
assert_exit "CLI not installed, upstream unchanged: exit 0" 0 "$?"
assert_contains "CLI not installed is reported" "$out" "NOT INSTALLED"

stub_sha="0000ffff"
out=$(run_check 2>&1)
assert_exit "CLI not installed, upstream changed: exit 1" 1 "$?"
assert_contains "upstream change is named" "$out" "upstream content changed"
stub_sha="abc123def456"
stub_current="1.18.0"

stub_latest="1.19.0"
out=$(run_check 2>&1)
assert_exit "installed CLI behind latest: exit 1" 1 "$?"
stub_latest="1.18.0"

UPSTREAM_MD="$FIXTURE_NEVER"
out=$(run_check 2>&1)
assert_exit "never synced: exit 1" 1 "$?"
assert_contains "never synced: last sync reads never" "$out" "last sync:  never"
UPSTREAM_MD="$FIXTURE_UP"

stub_latest=""
out=$(run_check 2>&1)
assert_exit "npm registry unreachable: exit 2" 2 "$?"
stub_latest="1.18.0"

stub_sha=""
out=$(run_check 2>&1)
assert_exit "upstream fetch fails: exit 2" 2 "$?"
stub_sha="abc123def456"

# Drift outranks unverifiable: the upstream check still runs when npm is down.
stub_latest=""
stub_sha="0000ffff"
out=$(run_check 2>&1)
assert_exit "npm unreachable, upstream changed: exit 1" 1 "$?"
assert_contains "npm unreachable: upstream change still named" "$out" "upstream content changed"
stub_latest="1.18.0"
stub_sha="abc123def456"

# A trailing space on a recorded value is not part of it.
FIXTURE_TRAIL="$TEST_TMPDIR/upstream-trailing.md"
printf -- '- Upstream SHA256: abc123def456  \n- CLI version at sync: 1.18.0 \n' >"$FIXTURE_TRAIL"
UPSTREAM_MD="$FIXTURE_TRAIL"
assert_eq "trailing space trimmed from recorded SHA" "abc123def456" "$(recorded_upstream_sha)"
out=$(run_check 2>&1)
assert_exit "trailing space on recorded SHA: exit 0" 0 "$?"
UPSTREAM_MD="$FIXTURE_UP"

# --- 9. --apply end to end, with firecrawl, npm, curl and uname stubbed ---------------
# A copy of the script runs in a fixture skill directory, so nothing can reach the
# real upstream.md. npm's layout in the stubs is its documented one: global
# executables go in {prefix}/bin on Unix and directly in {prefix} on Windows
# (https://docs.npmjs.com/cli/v11/configuring-npm/folders#executables).

APPLY="$TEST_TMPDIR/apply"
APPLY_SCRIPT="$APPLY/skill/scripts/update.sh"
APPLY_RECORD="$APPLY/skill/upstream.md"
APPLY_PRIOR_RECORD="prior upstream.md content"
mkdir -p "$APPLY/skill/scripts" "$APPLY/tools"
cp "$SCRIPT" "$APPLY_SCRIPT"
: >"$APPLY/skill/SKILL.md"

cat >"$APPLY/tools/npm" <<'EOF'
#!/usr/bin/env bash
case "$1" in
prefix)
  [[ "$STUB_NPM_PREFIX" != "FAIL" ]] || exit 1
  printf '%s\n' "$STUB_NPM_PREFIX"
  ;;
install)
  printf '%s\n' "$*" >>"$STUB_NPM_LOG"
  printf '%s\n' "$STUB_VERSION_AFTER_INSTALL" >"$STUB_VERSION_FILE"
  ;;
esac
EOF
cat >"$APPLY/tools/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while (($#)); do
  [[ "$1" == "-o" ]] && out="$2"
  shift
done
if [[ -n "$out" ]]; then
  printf 'upstream skill\n' >"$out"
else
  printf '{"version":"%s"}\n' "$STUB_LATEST"
fi
EOF
cat >"$APPLY/tools/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$STUB_UNAME"
EOF
cat >"$APPLY/tools/cygpath" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$STUB_CYGPATH_RESULT"
EOF
chmod +x "$APPLY/tools/npm" "$APPLY/tools/curl" "$APPLY/tools/uname" "$APPLY/tools/cygpath"

# Install a firecrawl stub in <dir> that reports the version in $STUB_VERSION_FILE.
place_firecrawl() {
  mkdir -p "$1"
  cat >"$1/firecrawl" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]] && cat "$STUB_VERSION_FILE"
exit 0
EOF
  chmod +x "$1/firecrawl"
}

# Fresh world for one case: no firecrawl anywhere, and a prior upstream.md.
reset_apply() {
  rm -rf "$APPLY/prefix" "$APPLY/launcher"
  mkdir -p "$APPLY/prefix/bin" "$APPLY/launcher"
  : >"$APPLY/npm.log"
  printf '%s\n' "$APPLY_PRIOR_RECORD" >"$APPLY_RECORD"
  printf '%s\n' "$1" >"$APPLY/version"
}

# run_stubbed_apply <npm global bin> <version after install> [uname] [npm prefix output]
run_stubbed_apply() {
  apply_out=$(
    PATH="$APPLY/tools:$APPLY/launcher:$1:$PATH" \
      STUB_NPM_PREFIX="${4:-$APPLY/prefix}" \
      STUB_NPM_LOG="$APPLY/npm.log" \
      STUB_VERSION_FILE="$APPLY/version" \
      STUB_VERSION_AFTER_INSTALL="$2" \
      STUB_LATEST="2.0.0" \
      STUB_UNAME="${3:-Linux}" \
      STUB_CYGPATH_RESULT="$APPLY/prefix" \
      bash "$APPLY_SCRIPT" --apply 2>&1
  )
  apply_exit=$?
}

# Refused or failed: exit 2, the prior record intact.
assert_apply_wrote_nothing() {
  assert_exit "$1: exit 2" 2 "$apply_exit"
  assert_eq "$1: upstream.md untouched" "$APPLY_PRIOR_RECORD" "$(cat "$APPLY_RECORD")"
}
assert_no_install() {
  assert_eq "$1: npm install never ran" "" "$(cat "$APPLY/npm.log")"
}

# npm owns the command and the install takes effect: the paired success case.
reset_apply "1.0.0"
place_firecrawl "$APPLY/prefix/bin"
run_stubbed_apply "$APPLY/prefix/bin" "2.0.0"
assert_exit "npm-owned: exit 0" 0 "$apply_exit"
assert_eq "npm-owned: install ran once" "install -g firecrawl-cli@latest" "$(cat "$APPLY/npm.log")"
assert_contains "npm-owned: records the new version" "$(cat "$APPLY_RECORD")" "CLI version at sync: 2.0.0"
assert_contains "npm-owned: records the rollback target" "$(cat "$APPLY_RECORD")" "rollback target): 1.0.0"

# A launcher ahead of npm's bin owns the command, behind the new version.
reset_apply "1.0.0"
place_firecrawl "$APPLY/launcher"
run_stubbed_apply "$APPLY/prefix/bin" "2.0.0"
assert_apply_wrote_nothing "launcher behind latest"
assert_no_install "launcher behind latest"
assert_contains "launcher behind latest: names the launcher as owner" "$apply_out" "$APPLY/launcher/firecrawl"

# The same launcher already at the new version would record itself as the rollback target.
reset_apply "2.0.0"
place_firecrawl "$APPLY/launcher"
run_stubbed_apply "$APPLY/prefix/bin" "2.0.0"
assert_apply_wrote_nothing "launcher at latest"
assert_no_install "launcher at latest"

# On Unix a command directly in the prefix is outside npm's bin.
reset_apply "1.0.0"
place_firecrawl "$APPLY/prefix"
run_stubbed_apply "$APPLY/prefix" "2.0.0"
assert_apply_wrote_nothing "Unix, command in the prefix itself"
assert_no_install "Unix, command in the prefix itself"

# npm's global prefix cannot be read, so ownership is unknown.
reset_apply "1.0.0"
place_firecrawl "$APPLY/prefix/bin"
run_stubbed_apply "$APPLY/prefix/bin" "2.0.0" "Linux" "FAIL"
assert_apply_wrote_nothing "npm prefix unreadable"
assert_no_install "npm prefix unreadable"
assert_contains "npm prefix unreadable: says so" "$apply_out" "npm prefix -g"

# The install succeeds and the command still reads the old version.
reset_apply "1.0.0"
place_firecrawl "$APPLY/prefix/bin"
run_stubbed_apply "$APPLY/prefix/bin" "1.0.0"
assert_apply_wrote_nothing "version unchanged after install"
assert_contains "version unchanged after install: names both versions" "$apply_out" "1.0.0"
assert_contains "version unchanged after install: names the expected version" "$apply_out" "2.0.0"

# Git Bash: the prefix prints as a CRLF-terminated Windows path and is the bin itself.
WINDOWS_PREFIX=$'C:\\fixture\\npm\r'
reset_apply "1.0.0"
place_firecrawl "$APPLY/prefix"
run_stubbed_apply "$APPLY/prefix" "2.0.0" "MINGW64_NT-10.0-26100" "$WINDOWS_PREFIX"
assert_exit "Windows, command in the prefix: exit 0" 0 "$apply_exit"
assert_contains "Windows, command in the prefix: records the new version" "$(cat "$APPLY_RECORD")" "CLI version at sync: 2.0.0"

reset_apply "1.0.0"
place_firecrawl "$APPLY/launcher"
run_stubbed_apply "$APPLY/prefix" "2.0.0" "MINGW64_NT-10.0-26100" "$WINDOWS_PREFIX"
assert_apply_wrote_nothing "Windows, launcher elsewhere"
assert_no_install "Windows, launcher elsewhere"

# No command at all is a fresh install, not a foreign owner.
PATH="$APPLY/no-such-dir" require_npm_owned_command
assert_exit "no firecrawl on PATH: not refused" 0 "$?"

# --- Final report ---------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
