#!/usr/bin/env bash
# Black-box contract tests for sync-run.sh (self-contained — ships with the plugin).
# Fixtures are built per case into a temp dir and driven through the REAL
# fleet-state.sh via its FLEET_STATE_* env overrides, so every `--from` projection
# and its exit status is the production one. Only the two siblings whose real work
# needs a machine — the `claude` CLI and cache-content-check.sh's git compare — are
# stubbed, through sync-run.sh's own SYNC_RUN_* overrides.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect a fixture's git usage into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sync-run.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 — got: $2" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# --- Fixture builders --------------------------------------------------------

# CASE_NUM must be incremented in the CALLER's shell before calling this, never
# inside it: `case_dir=$(new_case_dir)` runs in a subshell, so an assignment made
# in here is discarded and every case would silently reuse case-1's directory.
new_case_dir() {
  local case_dir="$TEST_TMPDIR/case-$CASE_NUM"
  mkdir -p "$case_dir/catalog" "$case_dir/journal" "$case_dir/stubs"
  echo "$case_dir"
}

write() { printf '%s' "$2" >"$1"; }

# A catalog entry with its own manifest, so `catalog_versions` resolves and the
# equality pre-filter and the downgrade guard are the production ones. Under
# FLEET_STATE_CATALOG_DIR the manifests live at
# <catalog dir>/<marketplace>/<source>/.claude-plugin/plugin.json, mirroring
# production's <installLocation>/<source>/.claude-plugin/plugin.json.
catalog_plugin() {
  local case_dir="$1" mp="$2" name="$3" version="$4"
  mkdir -p "$case_dir/catalog/$mp/$name/.claude-plugin"
  write "$case_dir/catalog/$mp/$name/.claude-plugin/plugin.json" \
    "{\"name\":\"$name\",\"version\":\"$version\"}"
}

# fleet-state.sh normalizes a project root to the platform's own spelling, so a
# fixture that records a projectPath has to record it the same way or the record
# never reads as `currentProject: true`.
norm_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

# The `claude` stub. Records every invocation and, on `plugin update`, rewrites the
# fixture's installed_plugins.json so the post-sweep re-read really moves.
write_claude_stub() {
  local case_dir="$1"
  cat >"$case_dir/stubs/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLAUDE_STUB_LOG"
verb="${1:-} ${2:-}"
case "$verb" in
"plugin marketplace")
  mp="${4:-}"
  if [[ -n "${CLAUDE_STUB_REFRESH_FAIL_MP:-}" && "$mp" == "$CLAUDE_STUB_REFRESH_FAIL_MP" ]]; then
    echo "Failed to clone marketplace repository" >&2
    exit 1
  fi
  echo "Successfully updated marketplace: $mp"
  ;;
"plugin update")
  id="${3:-}"
  scope="${5:-user}"
  if [[ -n "${CLAUDE_STUB_UPDATE_FAIL_ID:-}" && "$id" == "$CLAUDE_STUB_UPDATE_FAIL_ID" ]]; then
    echo "Plugin \"$id\" not found"
    exit 1
  fi
  if [[ -n "${CLAUDE_STUB_NOOP_ID:-}" && "$id" == "$CLAUDE_STUB_NOOP_ID" ]]; then
    cur=$(jq -r --arg id "$id" --arg sc "$scope" \
      'first(.plugins[$id][]? | select(.scope == $sc) | .version) // "0.0.0"' \
      "$CLAUDE_STUB_INSTALLED_JSON")
    echo "${id%@*} is already at the latest version ($cur)."
    exit 0
  fi
  new="${CLAUDE_STUB_NEW_VERSION:-9.9.9}"
  old=$(jq -r --arg id "$id" --arg sc "$scope" \
    'first(.plugins[$id][]? | select(.scope == $sc) | .version) // "0.0.0"' \
    "$CLAUDE_STUB_INSTALLED_JSON")
  tmp="$CLAUDE_STUB_INSTALLED_JSON.next"
  jq --arg id "$id" --arg sc "$scope" --arg v "$new" \
    '.plugins[$id] = [.plugins[$id][] | if .scope == $sc then .version = $v else . end]' \
    "$CLAUDE_STUB_INSTALLED_JSON" >"$tmp" && mv "$tmp" "$CLAUDE_STUB_INSTALLED_JSON"
  echo "Plugin \"${id%@*}\" updated from $old to $new for scope $scope. Restart to apply changes"
  ;;
"plugin install")
  echo "Installed ${3:-}"
  ;;
"plugin enable")
  echo "Enabled ${3:-}"
  ;;
*)
  echo "unexpected stub invocation: $*" >&2
  exit 9
  ;;
esac
exit 0
STUB
  chmod +x "$case_dir/stubs/claude"
}

# The cache-content-check.sh stub. Counts calls so the once-per-marketplace
# contract is asserted directly, and emits the JSON shape the real script emits.
write_cache_stub() {
  local case_dir="$1"
  cat >"$case_dir/stubs/cache-content-check.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CC_STUB_LOG"
mp=""
ids=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplace) mp="$2"; shift 2 ;;
  --ids) ids=1; shift ;;
  *) shift ;;
  esac
done
if ((ids == 1)); then
  printf '%s\n' "alpha@$mp"
  exit 0
fi
if [[ "${CC_STUB_BREAK_JSON:-0}" == "1" ]]; then
  echo "not json at all"
  exit 2
fi
cat <<JSON
{"marketplace":"$mp","scope":"user","checked":2,"match":1,"stale_content":1,
 "unverifiable":0,"skipped_absent_project_paths":0,
 "installs":[{"id":"alpha@$mp","verdict":"stale-content"},{"id":"beta@$mp","verdict":"match"}]}
JSON
exit 0
STUB
  chmod +x "$case_dir/stubs/cache-content-check.sh"
}

write_normalize_stub() {
  local case_dir="$1"
  cat >"$case_dir/stubs/normalize-enabled-plugins.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${NORMALIZE_STUB_LOG:-/dev/null}"
echo "already-sorted"
exit 0
STUB
  chmod +x "$case_dir/stubs/normalize-enabled-plugins.sh"
}

setup_case() {
  local case_dir="$1"
  write_claude_stub "$case_dir"
  write_cache_stub "$case_dir"
  write_normalize_stub "$case_dir"
  : >"$case_dir/claude.log"
  : >"$case_dir/cc.log"
  : >"$case_dir/normalize.log"
  [[ -f "$case_dir/user_settings.json" ]] || write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
}

# Runs sync-run.sh against a case fixture. Extra args are sync-run.sh's own.
run_sync() {
  local case_dir="$1"
  shift
  env \
    FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
    SYNC_RUN_CLAUDE_BIN="$case_dir/stubs/claude" \
    SYNC_RUN_CACHE_CHECK="$case_dir/stubs/cache-content-check.sh" \
    SYNC_RUN_NORMALIZE="$case_dir/stubs/normalize-enabled-plugins.sh" \
    CLAUDE_STUB_LOG="$case_dir/claude.log" \
    CLAUDE_STUB_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    CC_STUB_LOG="$case_dir/cc.log" \
    NORMALIZE_STUB_LOG="$case_dir/normalize.log" \
    PATH="$case_dir/stubs:$PATH" \
    "${EXTRA_ENV[@]}" \
    bash "$SCRIPT" "$@" 2>"$case_dir/stderr.txt"
}

# ============================================================================
# Case: audit issues ZERO mutating CLI calls, and still takes every read
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.3.0
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]}
}'
write "$case_dir/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true}}'
setup_case "$case_dir"
EXTRA_ENV=()
# The policy argument is deliberately the unset placeholder token here: it is the
# one value a caller can pass by mistake, and it must fall back to `ask` and be
# named rather than swallowed.
out=$(run_sync "$case_dir" --marketplace market1 --audit --install-new '${user_config.install_new}')
rc=$?
assert_exit "audit: exit 0" 0 "$rc"
assert_eq "invalid policy: falls back to ask" "ask" "$(jq -r '.install_new' <<<"$out")"
assert_eq "invalid policy: the value is named, not swallowed" '${user_config.install_new}' \
  "$(jq -r '.install_new_invalid' <<<"$out")"
assert_eq "audit: mode is audit" "audit" "$(jq -r '.mode' <<<"$out")"
assert_eq "audit: zero claude invocations" "0" "$(wc -l <"$case_dir/claude.log" | tr -d ' ')"
assert_eq "audit: refresh is a prediction" "true" "$(jq -r '.marketplaces[0].refresh.predicted' <<<"$out")"
assert_eq "audit: the update candidate is predicted, not performed" "1" \
  "$(jq -r '.marketplaces[0].user_sweep.would_update | length' <<<"$out")"
assert_eq "audit: nothing recorded as updated" "0" \
  "$(jq -r '.marketplaces[0].user_sweep.updated | length' <<<"$out")"
assert_eq "audit: the scratch run directory is removed on exit" "absent" \
  "$([[ -d "$(jq -r '.run_dir' <<<"$out")" ]] && echo present || echo absent)"

# ============================================================================
# Case: sync calls the cache checker exactly ONCE per marketplace, and reads the
# stale ids out of that call's own JSON
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.3.0
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]}
}'
write "$case_dir/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true}}'
setup_case "$case_dir"
EXTRA_ENV=(CLAUDE_STUB_NEW_VERSION=0.3.0)
out=$(run_sync "$case_dir" --marketplace market1 --journal-root "$case_dir/journal")
rc=$?
assert_exit "sync: exit 0" 0 "$rc"
assert_eq "sync: checker called exactly once" "1" "$(wc -l <"$case_dir/cc.log" | tr -d ' ')"
assert_eq "sync: that one call was the JSON form, not --ids" "0" \
  "$(grep -c -- '--ids' "$case_dir/cc.log")"
assert_eq "sync: stale ids came from the JSON" "alpha@market1" \
  "$(jq -r '.marketplaces[0].cache_content.stale_ids[0]' <<<"$out")"
assert_eq "sync: cache source is the JSON" "json" \
  "$(jq -r '.marketplaces[0].cache_content.source' <<<"$out")"
assert_eq "sync: the update is reported as a forward move" "forward" \
  "$(jq -r '.marketplaces[0].user_sweep.updated[0].direction' <<<"$out")"
assert_eq "sync: old version came from the pre-mutation snapshot" "0.1.0" \
  "$(jq -r '.marketplaces[0].user_sweep.updated[0].old' <<<"$out")"
assert_eq "sync: new version came from the CLI's own line" "0.3.0" \
  "$(jq -r '.marketplaces[0].user_sweep.updated[0].new' <<<"$out")"
assert_eq "sync: the journal recorded the mutating call" "1" \
  "$(grep -c 'claude plugin update alpha@market1' "$(jq -r '.run_dir' <<<"$out")/journal.log")"
assert_eq "sync: the digest is also written to the run directory" "market1" \
  "$(jq -r '.marketplaces[0].name' "$(jq -r '.run_dir' <<<"$out")/digest.json")"

# ============================================================================
# Case: a failing `claude plugin update` lands in `failed`, never in `updated`
# (the rc=${PIPESTATUS[0]} guarantee — tee succeeds whenever it can write the log)
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.3.0
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]}
}'
write "$case_dir/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true}}'
setup_case "$case_dir"
EXTRA_ENV=(CLAUDE_STUB_UPDATE_FAIL_ID=alpha@market1)
out=$(run_sync "$case_dir" --marketplace market1 --journal-root "$case_dir/journal")
assert_eq "failed update: recorded as failed" "1" \
  "$(jq -r '.marketplaces[0].user_sweep.failed | length' <<<"$out")"
assert_eq "failed update: NOT recorded as updated" "0" \
  "$(jq -r '.marketplaces[0].user_sweep.updated | length' <<<"$out")"
assert_eq "failed update: the CLI's own status is kept" "1" \
  "$(jq -r '.marketplaces[0].user_sweep.failed[0].rc' <<<"$out")"

# ============================================================================
# Case: a proven downgrade is WITHHELD by default and acted on only with
# --allow-downgrade, where it renders as downgraded and never as updated
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.1.0
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.5.0"}]}
}'
write "$case_dir/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true}}'
setup_case "$case_dir"
EXTRA_ENV=()
out=$(run_sync "$case_dir" --marketplace market1 --journal-root "$case_dir/journal")
assert_eq "downgrade: withheld by default" "1" \
  "$(jq -r '.marketplaces[0].user_sweep.withheld_downgrades | length' <<<"$out")"
assert_eq "downgrade: no update issued for it" "0" \
  "$(grep -c 'plugin update' "$case_dir/claude.log")"
assert_eq "downgrade: both versions carried for the report" "0.5.0 0.1.0" \
  "$(jq -r '.marketplaces[0].user_sweep.withheld_downgrades[0] | "\(.installed) \(.catalog)"' <<<"$out")"

CASE_NUM=$((CASE_NUM + 1))
case_dir2=$(new_case_dir)
cp -r "$case_dir"/. "$case_dir2"/
: >"$case_dir2/claude.log"
: >"$case_dir2/cc.log"
write "$case_dir2/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.5.0"}]}
}'
write "$case_dir2/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir2/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
EXTRA_ENV=(CLAUDE_STUB_NEW_VERSION=0.1.0)
out=$(run_sync "$case_dir2" --marketplace market1 --allow-downgrade --journal-root "$case_dir2/journal")
assert_eq "--allow-downgrade: the rollback is issued" "1" \
  "$(grep -c 'plugin update alpha@market1' "$case_dir2/claude.log")"
assert_eq "--allow-downgrade: it renders as downgraded" "1" \
  "$(jq -r '.marketplaces[0].downgraded | length' <<<"$out")"
assert_eq "--allow-downgrade: never as updated" "0" \
  "$(jq -r '.marketplaces[0].user_sweep.updated | length' <<<"$out")"
assert_eq "--allow-downgrade: recorded in the digest" "true" \
  "$(jq -r '.allow_downgrade' <<<"$out")"

# ============================================================================
# Case: an install gap under the `ask` policy stops before Step 4, and the narrow
# --only-install re-entry then installs and enables against the SAME run directory
# without re-running the cache checker
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.2.0
catalog_plugin "$case_dir" market1 beta 0.2.0
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]}
}'
write "$case_dir/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}, {"name": "beta", "source": "beta"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true}}'
setup_case "$case_dir"
EXTRA_ENV=(CLAUDE_STUB_NEW_VERSION=0.2.0)
out=$(run_sync "$case_dir" --marketplace market1 --install-new ask --journal-root "$case_dir/journal")
assert_eq "ask: the sweep still ran before the stop" "1" \
  "$(jq -r '.marketplaces[0].user_sweep.updated | length' <<<"$out")"
assert_eq "ask: stops before Step 4" "true" \
  "$(jq -r '.marketplaces[0].stopped_before_install' <<<"$out")"
assert_eq "ask: the gap is reported" "beta@market1" \
  "$(jq -r '.marketplaces[0].install_gap[0]' <<<"$out")"
assert_eq "ask: nothing installed" "0" "$(grep -c 'plugin install' "$case_dir/claude.log")"
assert_eq "ask: the checker still ran exactly once" "1" "$(wc -l <"$case_dir/cc.log" | tr -d ' ')"

run_dir=$(jq -r '.run_dir' <<<"$out")
out2=$(run_sync "$case_dir" --marketplace market1 --only-install beta@market1 --run-dir "$run_dir")
assert_exit "--only-install: exit 0" 0 $?
assert_eq "--only-install: the chosen id is installed" "1" \
  "$(grep -c 'plugin install beta@market1' "$case_dir/claude.log")"
assert_eq "--only-install: reuses the same run directory" "$run_dir" "$(jq -r '.run_dir' <<<"$out2")"
assert_eq "--only-install: the first pass's sweep row survives into the second digest" "alpha@market1" \
  "$(jq -r '.marketplaces[0].user_sweep.updated[0].id' <<<"$out2")"
assert_eq "--only-install: and its project_root does too" "$(jq -r '.marketplaces[0].project_root' <<<"$out")" \
  "$(jq -r '.marketplaces[0].project_root' <<<"$out2")"
assert_eq "--only-install: the checker is NOT run a second time" "1" \
  "$(wc -l <"$case_dir/cc.log" | tr -d ' ')"
assert_eq "--only-install: the cache finding survives into the second digest" "alpha@market1" \
  "$(jq -r '.marketplaces[0].cache_content.stale_ids[0]' <<<"$out2")"
assert_eq "--only-install: the normalizer wrote user scope once after the install" "1" \
  "$(grep -cv -- '--report-project' "$case_dir/normalize.log")"
assert_eq "--only-install: and only INSPECTED the project-scope map" "1" \
  "$(grep -c -- '--report-project' "$case_dir/normalize.log")"

# ============================================================================
# Case: `none` reports the gap and installs nothing; `all` installs it
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.1.0
catalog_plugin "$case_dir" market1 beta 0.2.0
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]}
}'
write "$case_dir/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}, {"name": "beta", "source": "beta"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true}}'
setup_case "$case_dir"
EXTRA_ENV=()
out=$(run_sync "$case_dir" --marketplace market1 --install-new none --journal-root "$case_dir/journal")
assert_eq "none: nothing installed" "0" "$(grep -c 'plugin install' "$case_dir/claude.log")"
assert_eq "none: the gap is still reported" "beta@market1" \
  "$(jq -r '.marketplaces[0].install_gap[0]' <<<"$out")"
assert_eq "none: the run did not stop before Step 4" "false" \
  "$(jq -r '.marketplaces[0].stopped_before_install' <<<"$out")"

CASE_NUM=$((CASE_NUM + 1))
case_dir2=$(new_case_dir)
cp -r "$case_dir"/. "$case_dir2"/
: >"$case_dir2/claude.log"
: >"$case_dir2/cc.log"
: >"$case_dir2/normalize.log"
write "$case_dir2/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir2/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
out=$(run_sync "$case_dir2" --marketplace market1 --install-new all --journal-root "$case_dir2/journal")
assert_eq "all: the gap is installed" "1" "$(grep -c 'plugin install beta@market1' "$case_dir2/claude.log")"
assert_eq "all: the normalizer heals the key order the install disturbed" "1" \
  "$(grep -cv -- '--report-project' "$case_dir2/normalize.log")"

# ============================================================================
# Case: an empty projection that EXITED 2 is an error, never "nothing to do"
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.1.0
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]}
}'
write "$case_dir/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true}}'
setup_case "$case_dir"
# A fleet-state wrapper that answers reads normally and rejects every projection
# the way the real script rejects a malformed report: exit 2, EMPTY stdout.
cat >"$case_dir/stubs/fleet-state.sh" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "--ids" ]]; then
    echo "ERROR: --from report is not the marketplace it claims" >&2
    exit 2
  fi
done
exec bash "$SCRIPT_DIR/fleet-state.sh" "\$@"
STUB
chmod +x "$case_dir/stubs/fleet-state.sh"
EXTRA_ENV=(SYNC_RUN_FLEET_STATE="$case_dir/stubs/fleet-state.sh")
out=$(run_sync "$case_dir" --marketplace market1 --journal-root "$case_dir/journal")
assert_contains "exit-2 projection: reported as an error" \
  "$(jq -r '.marketplaces[0].errors | join(" | ")' <<<"$out")" "projection failed"
assert_eq "exit-2 projection: the sweep is not reported as done" "0" \
  "$(jq -r '.marketplaces[0].user_sweep.updated | length' <<<"$out")"
assert_eq "exit-2 projection: no update was issued off an empty list" "0" \
  "$(grep -c 'plugin update' "$case_dir/claude.log")"

# ============================================================================
# Case: --all loops every marketplace, and one marketplace's failure does not
# abort the sweep for the rest
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.1.0
catalog_plugin "$case_dir" market2 gamma 0.1.0
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}],
    "gamma@market2": [{"scope": "user", "installPath": "z", "version": "0.1.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" "{
  \"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m1\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"},
  \"market2\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m2\"}, \"installLocation\": \"$case_dir/mkt2\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}
}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}]}'
write "$case_dir/catalog/market2.json" '{"plugins": [{"name": "gamma", "source": "gamma"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true, "gamma@market2": true}}'
setup_case "$case_dir"
EXTRA_ENV=(CLAUDE_STUB_REFRESH_FAIL_MP=market1)
out=$(run_sync "$case_dir" --all --journal-root "$case_dir/journal")
rc=$?
assert_exit "--all: exit 0 despite a per-marketplace failure" 0 "$rc"
assert_eq "--all: both marketplaces are in the digest" "2" "$(jq -r '.marketplaces | length' <<<"$out")"
assert_contains "--all: the failing marketplace names its failure inline" \
  "$(jq -r '.marketplaces[] | select(.name == "market1") | .errors | join(" | ")' <<<"$out")" \
  "marketplace refresh failed"
assert_eq "--all: its install/enable maintenance is deferred, not silently skipped" "true" \
  "$(jq -r '.marketplaces[] | select(.name == "market1") | .install_enable_deferred' <<<"$out")"
assert_eq "--all: the other marketplace still refreshed" "0" \
  "$(jq -r '.marketplaces[] | select(.name == "market2") | .refresh.rc' <<<"$out")"
assert_eq "--all: the checker ran once per marketplace" "2" "$(wc -l <"$case_dir/cc.log" | tr -d ' ')"

# ============================================================================
# Case: an enable gap is filled at user scope and REPORTED at project scope
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
catalog_plugin "$case_dir" market1 alpha 0.1.0
catalog_plugin "$case_dir" market1 delta 0.1.0
ppath=$(norm_path "$case_dir")
write "$case_dir/installed_plugins.json" "{
  \"version\": 1,
  \"plugins\": {
    \"alpha@market1\": [{\"scope\": \"user\", \"installPath\": \"y\", \"version\": \"0.1.0\"}],
    \"delta@market1\": [{\"scope\": \"project\", \"projectPath\": \"$ppath\", \"installPath\": \"d\", \"version\": \"0.1.0\"}]
  }
}"
write "$case_dir/known_marketplaces.json" "{\"market1\": {\"source\": {\"source\": \"github\", \"repo\": \"e/m\"}, \"installLocation\": \"$case_dir/mkt\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}, {"name": "delta", "source": "delta"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {}}'
setup_case "$case_dir"
EXTRA_ENV=(CLAUDE_PROJECT_DIR="$case_dir" CLAUDE_STUB_NOOP_ID=delta@market1)
out=$(run_sync "$case_dir" --marketplace market1 --install-new none --journal-root "$case_dir/journal")
assert_eq "no-op update: the in-repo sweep called the CLI for the record" "1" \
  "$(grep -c 'plugin update delta@market1' "$case_dir/claude.log")"
assert_eq "no-op update: an already-current id is NOT an Updated row" "0" \
  "$(jq -r '.marketplaces[0].in_repo.updated | length' <<<"$out")"
assert_eq "no-op update: and is not a downgrade either" "0" \
  "$(jq -r '.marketplaces[0].downgraded | length' <<<"$out")"
assert_eq "report inputs: the marketplace's autoUpdate rides the digest" "null" \
  "$(jq -r '.marketplaces[0] | has("auto_update") | if . then "null" else "missing" end' <<<"$out")"
assert_eq "report inputs: the stale-project-record count rides the digest" "0" \
  "$(jq -r '.marketplaces[0].stale_project_records.records' <<<"$out")"
assert_eq "enable gap: the user-scope id is enabled" "1" \
  "$(grep -c 'plugin enable alpha@market1 -s user' "$case_dir/claude.log")"
assert_eq "enable gap: no project-scope enable is ever issued" "0" \
  "$(grep -c 'plugin enable .* -s project' "$case_dir/claude.log")"
assert_eq "enable gap: the project-scope row is reported with its path" "$ppath" \
  "$(jq -r '.marketplaces[0].project_enable_rows[0].project_path' <<<"$out")"

# ============================================================================
# Case: sync mode without --journal-root is a usage error, not a silent scratch run
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
setup_case "$case_dir"
EXTRA_ENV=()
out=$(run_sync "$case_dir" --marketplace market1)
rc=$?
assert_exit "no journal root: exit 2" 2 "$rc"
assert_contains "no journal root: names the flag" "$(cat "$case_dir/stderr.txt")" "--journal-root"

# ============================================================================
if ((FAILED > 0)); then
  printf '\n%d test(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf '\nAll tests passed\n'
