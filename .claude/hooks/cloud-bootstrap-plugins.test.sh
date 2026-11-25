#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
# shellcheck source=../../scripts/test-git-helpers.sh
source "$repo_root/scripts/test-git-helpers.sh"

BOOTSTRAP="${CLOUD_BOOTSTRAP_SCRIPT:-$repo_root/.claude/cloud-bootstrap.sh}"

for tool in jq git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool unavailable; the accounting block is gated on it anyway"
    exit 0
  fi
done

if [[ ! -f "$BOOTSTRAP" ]]; then
  echo "FAIL: bootstrap script not found: $BOOTSTRAP"
  exit 1
fi

host_executes_extensionless_claude_stub() {
  local d stub out
  d="$(mktemp -d)"
  mkdir -p "$d/node_modules/.bin"
  stub="$d/node_modules/.bin/claude"
  printf '#!/usr/bin/env bash\nprintf stub-ok\n' >"$stub"
  chmod +x "$stub"
  out="$("$stub" 2>/dev/null || true)"
  rm -rf "$d"
  [[ "$out" == "stub-ok" ]]
}
set +e
host_executes_extensionless_claude_stub
stub_rc=$?
set -e
if [[ "$stub_rc" -ne 0 ]]; then
  echo "SKIP (host: extensionless node_modules/.bin/claude stub does not run): cloud-bootstrap plugin accounting"
  echo "PASS=0 FAIL=0 SKIPPED=1"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract_fail=0

if ! grep -q '^# --- Python CI deps' "$BOOTSTRAP"; then
  echo "FAIL: end anchor '# --- Python CI deps' not found in $BOOTSTRAP"
  echo "      Without it the extraction runs to end of file and would execute the"
  echo "      script's pip, curl, install and git fetch steps once per case."
  extract_fail=1
fi
if ! grep -q '^claude_bin=' "$BOOTSTRAP"; then
  echo "FAIL: start anchor '^claude_bin=' not found in $BOOTSTRAP"
  extract_fail=1
fi
if [[ "$extract_fail" -ne 0 ]]; then
  echo "Re-point the anchors in this suite at the plugin block in $BOOTSTRAP."
  exit 1
fi

BLOCK="$TMP/plugin-block.sh"
{
  # shellcheck disable=SC2016  # the preamble is fixture text; $1 must stay literal
  printf '#!/usr/bin/env bash\nset -euo pipefail\nrepo_root="$1"\ncd -- "$repo_root"\n'
  awk '/^claude_bin=/ {p = 1} /^# --- Python CI deps/ {p = 0} p' "$BOOTSTRAP"
} >"$BLOCK"

if ! grep -q 'plugin list --json' "$BLOCK"; then
  echo "FAIL: extracted block does not call \`plugin list --json\`; the \`claude_bin=\` anchor moved"
  extract_fail=1
fi
if ! grep -q 'newly installed' "$BLOCK"; then
  echo "FAIL: extracted block does not print the summary line; the extraction is not the plugin block"
  extract_fail=1
fi
if grep -q 'pip install' "$BLOCK"; then
  echo "FAIL: extracted block reaches past the plugin section into the Python CI deps install"
  echo "      ($(wc -l <"$BLOCK") lines extracted). It would run pip, curl and git fetch per case."
  extract_fail=1
fi
if ! bash -n "$BLOCK" 2>/dev/null; then
  echo "FAIL: extracted block is not valid bash; the anchors no longer bracket a whole block"
  extract_fail=1
fi
if [[ "$extract_fail" -ne 0 ]]; then
  echo "Re-point the anchors in this suite at the plugin block in $BOOTSTRAP."
  exit 1
fi

pass=0
fail=0
ok() {
  echo "ok   - $1"
  pass=$((pass + 1))
}
bad() {
  echo "not ok - $1"
  fail=$((fail + 1))
}

BOTH_USER='[{"id":"alpha@melodic-software","scope":"user","enabled":true},
            {"id":"beta@melodic-software","scope":"user","enabled":true}]'
BOTH_DUPLICATED='[{"id":"alpha@melodic-software","scope":"project","enabled":true},
                  {"id":"alpha@melodic-software","scope":"user","enabled":true},
                  {"id":"beta@melodic-software","scope":"project","enabled":true},
                  {"id":"beta@melodic-software","scope":"user","enabled":true}]'
BETA_PROJECT_ONLY='[{"id":"alpha@melodic-software","scope":"user","enabled":true},
                    {"id":"beta@melodic-software","scope":"project","enabled":true}]'
BETA_DISABLED='[{"id":"alpha@melodic-software","scope":"user","enabled":true},
                {"id":"beta@melodic-software","scope":"user","enabled":false}]'
BETA_ENABLED_STRING='[{"id":"alpha@melodic-software","scope":"user","enabled":true},
                      {"id":"beta@melodic-software","scope":"user","enabled":"true"}]'
BETA_DISABLED_STRING='[{"id":"alpha@melodic-software","scope":"user","enabled":true},
                       {"id":"beta@melodic-software","scope":"user","enabled":"false"}]'
NONE='[]'

REG_BOTH_HEAD='{"plugins":{
  "alpha@melodic-software":[{"scope":"user","gitCommitSha":"@HEAD@"}],
  "beta@melodic-software":[{"scope":"user","gitCommitSha":"@HEAD@"}]}}'
REG_BOTH_FIRST='{"plugins":{
  "alpha@melodic-software":[{"scope":"user","gitCommitSha":"@FIRST@"}],
  "beta@melodic-software":[{"scope":"user","gitCommitSha":"@FIRST@"}]}}'
REG_BETA_SHA_ABSENT='{"plugins":{
  "alpha@melodic-software":[{"scope":"user","gitCommitSha":"@HEAD@"}],
  "beta@melodic-software":[{"scope":"user"}]}}'
REG_BETA_SHA_NULL='{"plugins":{
  "alpha@melodic-software":[{"scope":"user","gitCommitSha":"@HEAD@"}],
  "beta@melodic-software":[{"scope":"user","gitCommitSha":null}]}}'
REG_BETA_UNKNOWN='{"plugins":{
  "alpha@melodic-software":[{"scope":"user","gitCommitSha":"@HEAD@"}],
  "beta@melodic-software":[{"scope":"user","gitCommitSha":"0123456789abcdef0123456789abcdef01234567"}]}}'

OUT=""
RC=0
run_case() {
  local name="$1" before="$2" after="$3" registry="$4" registry_after="$5"
  local fx="$TMP/$name"
  mkdir -p "$fx/.claude" "$fx/node_modules/.bin" "$fx/plugins/alpha" "$fx/plugins/beta" "$fx/cfg/plugins"

  local default_settings='{"enabledPlugins":{"alpha@melodic-software":true,"beta@melodic-software":true}}'
  printf '%s\n' "${CASE_SETTINGS:-$default_settings}" >"$fx/.claude/settings.json"
  local empty_fleet='{"enabledPlugins":{}}'
  local fleet_env=(CLOUD_BOOTSTRAP_FLEET_LIST="$fx/fleet.json")
  if [[ "${CASE_FLEET:-}" == ABSENT ]]; then
    fleet_env=(CLOUD_BOOTSTRAP_FLEET_LIST="$fx/no-fleet-list.json")
  else
    printf '%s\n' "${CASE_FLEET:-$empty_fleet}" >"$fx/fleet.json"
  fi
  if [[ -n "${CASE_MARKETPLACE:-}" ]]; then
    mkdir -p "$fx/.claude-plugin"
    printf '%s\n' "$CASE_MARKETPLACE" >"$fx/.claude-plugin/marketplace.json"
  fi
  printf 'a\n' >"$fx/plugins/alpha/f.txt"
  printf 'b\n' >"$fx/plugins/beta/f.txt"

  git_init_test_repo "$fx" >/dev/null
  git_test_config "$fx" add -A
  git_test_config "$fx" commit -qm one
  local first head
  first="$(git_test_config "$fx" rev-parse HEAD)"
  printf 'a2\n' >>"$fx/plugins/alpha/f.txt"
  git_test_config "$fx" add -A
  git_test_config "$fx" commit -qm two
  head="$(git_test_config "$fx" rev-parse HEAD)"

  local clone_head=""
  if [[ -n "${CASE_CLONE:-}" ]]; then
    local location="$fx"
    if [[ "$CASE_CLONE" != self ]]; then
      location="$TMP/$name-clone"
      git_test_config "$fx" clone -q "$fx" "$location"
      if [[ "$CASE_CLONE" == behind ]]; then
        git_test_config "$location" reset -q --hard "$first"
      else
        printf 'a3\n' >>"$location/plugins/alpha/f.txt"
        git_test_config "$location" add -A
        git_test_config "$location" commit -qm three
      fi
      clone_head="$(git_test_config "$location" rev-parse HEAD)"
    fi
    if [[ "${CASE_SOURCE_SHAPE:-}" == object ]]; then
      printf '[{"name":"melodic-software","source":{"source":"github","repo":"melodic-software/claude-code-plugins"},"installLocation":"%s"}]\n' "$location" \
        >"$fx/marketplace-entry.json"
    else
      printf '[{"name":"melodic-software","source":"github","installLocation":"%s"}]\n' "$location" \
        >"$fx/marketplace-entry.json"
    fi
    [[ -z "${CASE_UPDATE_FAILS:-}" ]] || : >"$fx/update-fails"
  fi

  local subst="s/@HEAD@/$head/g; s/@FIRST@/$first/g; s/@CLONE@/$clone_head/g"
  if [[ "$registry" != "MISSING" ]]; then
    printf '%s\n' "$registry" | sed "$subst" >"$fx/cfg/plugins/installed_plugins.json"
  fi
  if [[ "$registry_after" != "NONE" ]]; then
    printf '%s\n' "$registry_after" | sed "$subst" >"$fx/registry-after.json"
  fi

  printf '%s\n' "$before" >"$fx/list-before.json"
  printf '%s\n' "$after" >"$fx/list-after.json"

  cat >"$fx/node_modules/.bin/claude" <<'STUB'
#!/usr/bin/env bash
fx="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
case "$*" in
*"marketplace list"*)
  if [[ -f "$fx/marketplace-entry.json" ]]; then
    cat "$fx/marketplace-entry.json"
  else
    printf '[{"name":"melodic-software"}]\n'
  fi
  ;;
*"marketplace update"*)
  printf '%s\n' "$*" >>"$fx/calls.log"
  if [[ -f "$fx/update-fails" ]]; then exit 1; fi
  ;;
*"plugin list --json"*)
  if [[ -f "$fx/.listed" ]]; then
    cat "$fx/list-after.json"
  else
    : >"$fx/.listed"
    cat "$fx/list-before.json"
  fi
  ;;
*"plugin install"*)
  if [[ -f "$fx/registry-after.json" ]]; then
    cp "$fx/registry-after.json" "$fx/cfg/plugins/installed_plugins.json"
  fi
  ;;
*"plugin enable"*) exit 1 ;;
*) : ;;
esac
STUB
  chmod +x "$fx/node_modules/.bin/claude"

  set +e
  OUT="$(env "${fleet_env[@]}" CLAUDE_CONFIG_DIR="$fx/cfg" bash "$BLOCK" "$fx" 2>&1)"
  RC=$?
  set -e
  if [[ -f "$fx/calls.log" ]]; then
    OUT+=$'\n'"calls: $(tr '\n' ';' <"$fx/calls.log")"
  fi

  if [[ "$RC" -eq 0 ]]; then
    ok "$name: the block exits 0, so the rest of the bootstrap still runs"
  else
    bad "$name: the block exited $RC, which under \`set -e\` aborts the whole bootstrap"
    printf '%s\n' "$OUT" | sed 's/^/       /'
  fi
}

expect() {
  local name="$1" needle="$2"
  if grep -qF -- "$needle" <<<"$OUT"; then
    ok "$name"
  else
    bad "$name (expected: $needle)"
    printf '%s\n' "$OUT" | sed 's/^/       /'
  fi
}

refute() {
  local name="$1" needle="$2"
  if grep -qF -- "$needle" <<<"$OUT"; then
    bad "$name (unexpected: $needle)"
    printf '%s\n' "$OUT" | sed 's/^/       /'
  else
    ok "$name"
  fi
}

run_case steady "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a settled catalog reports no work and no failures" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"

run_case duplicated "$BOTH_DUPLICATED" "$BOTH_DUPLICATED" "$REG_BOTH_HEAD" NONE
expect "the real project+user duplicate listing passes" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"

run_case fresh "$NONE" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a first-run install counts as installed, not failed" \
  "plugins 2 declared, 2 newly installed, 0 refreshed, 0 failed"

run_case refreshed "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_FIRST" "$REG_BOTH_HEAD"
expect "a healthy refresh is not a failure even though \`plugin enable\` exits 1" \
  "plugins 2 declared, 0 newly installed, 1 refreshed, 0 failed"

run_case project_only "$BETA_PROJECT_ONLY" "$BETA_PROJECT_ONLY" "$REG_BOTH_HEAD" NONE
expect "a plugin present only at project scope is a failure" \
  "beta@melodic-software failed verification after no action: not installed at user scope"
expect "and is named in the summary" \
  "0 refreshed, 1 failed: beta@melodic-software"

run_case disabled "$BETA_DISABLED" "$BETA_DISABLED" "$REG_BOTH_HEAD" NONE
expect "a plugin installed at user scope but disabled is a failure" \
  "beta@melodic-software failed verification after no action: installed at user scope but not enabled"

BETA_DEFAULT_DISABLED='{"plugins":[{"name":"alpha"},{"name":"beta","defaultEnabled":false}]}'

CASE_MARKETPLACE="$BETA_DEFAULT_DISABLED" \
  run_case default_disabled_fresh "$NONE" "$BETA_DISABLED" "$REG_BOTH_HEAD" NONE
expect "a fresh install left disabled by the catalog counts as installed, not failed" \
  "plugins 2 declared, 2 newly installed, 0 refreshed, 0 failed"
refute "and is not named as a failure" \
  "beta@melodic-software failed verification"

CASE_MARKETPLACE="$BETA_DEFAULT_DISABLED" \
  run_case default_disabled_steady "$BETA_DISABLED" "$BETA_DISABLED" "$REG_BOTH_HEAD" NONE
expect "a settled catalog-disabled plugin reports no work and no failures" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"

CASE_MARKETPLACE="$BETA_DEFAULT_DISABLED" \
  run_case default_disabled_project_only "$BETA_PROJECT_ONLY" "$BETA_PROJECT_ONLY" "$REG_BOTH_HEAD" NONE
expect "a catalog-disabled plugin missing from user scope is still a failure" \
  "beta@melodic-software failed verification after no action: not installed at user scope"

CASE_MARKETPLACE="$BETA_DEFAULT_DISABLED" \
  run_case default_disabled_stale "$BETA_DISABLED" "$BETA_DISABLED" "$REG_BETA_SHA_NULL" NONE
expect "a catalog-disabled plugin is still snapshot-verified" \
  "beta@melodic-software failed verification after no action: cannot verify snapshot: no user-scope gitCommitSha recorded"

CASE_MARKETPLACE="$BETA_DEFAULT_DISABLED" \
  run_case default_disabled_enabled_string "$BETA_DISABLED_STRING" "$BETA_DISABLED_STRING" "$REG_BOTH_HEAD" NONE
expect "a catalog-disabled plugin with enabled as the string \"false\" still fails" \
  "beta@melodic-software failed verification after no action: installed at user scope but not enabled"

run_case enabled_string "$BETA_ENABLED_STRING" "$BETA_ENABLED_STRING" "$REG_BOTH_HEAD" NONE
expect "enabled as the string \"true\" is rejected, not accepted" \
  "beta@melodic-software failed verification after no action: installed at user scope but not enabled"

run_case sha_absent "$BOTH_USER" "$BOTH_USER" "$REG_BETA_SHA_ABSENT" NONE
expect "an absent gitCommitSha cannot be verified and fails closed" \
  "beta@melodic-software failed verification after no action: cannot verify snapshot: no user-scope gitCommitSha recorded"

run_case sha_null "$BOTH_USER" "$BOTH_USER" "$REG_BETA_SHA_NULL" NONE
expect "a null gitCommitSha cannot be verified and fails closed" \
  "beta@melodic-software failed verification after no action: cannot verify snapshot: no user-scope gitCommitSha recorded"

run_case registry_missing "$BOTH_USER" "$BOTH_USER" MISSING NONE
expect "a missing installed_plugins.json fails every plugin closed" \
  "cannot verify snapshot: no plugin registry at"
expect "and both plugins are named" \
  "2 failed: alpha@melodic-software, beta@melodic-software"

run_case unknown_sha "$BOTH_USER" "$BOTH_USER" "$REG_BETA_UNKNOWN" NONE
expect "a recorded commit this clone does not have fails closed" \
  "cannot verify snapshot: installed from commit 0123456789abcdef0123456789abcdef01234567, which this clone does not have"

run_case stale_refresh_stuck "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_FIRST" NONE
expect "a refresh that did not take is reported with the directory that changed" \
  "alpha@melodic-software failed verification after refresh: plugins/alpha changed between the installed commit"
refute "and a plugin whose own directory did not change is not called stale" \
  "beta@melodic-software failed verification"
expect "an attempted plugin that failed is counted once, as failed only" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 1 failed: alpha@melodic-software"

run_case unreadable "$BOTH_USER" 'not json at all' "$REG_BOTH_HEAD" NONE
expect "an unreadable plugin list fails the whole batch" \
  "none could be verified, see the warning above"
expect "with one warning for the batch" \
  "could not read \`claude plugin list --json\`; no plugin could be verified"
refute "and no per-plugin flood" \
  "failed verification after"

CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true}}' \
  CASE_FLEET='{"enabledPlugins":{"alpha@melodic-software":true,"beta@melodic-software":true,"gamma@elsewhere":true}}' \
  run_case fleet_union "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a fleet entry beyond the settings block counts as enabled" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"

CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true,"beta@melodic-software":false}}' \
  CASE_FLEET='{"enabledPlugins":{"alpha@melodic-software":true,"beta@melodic-software":true}}' \
  run_case fleet_opt_out "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a settings false opts out of a fleet entry" \
  "plugins 1 declared, 0 newly installed, 0 refreshed, 0 failed"

CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true}}' \
  CASE_FLEET=ABSENT \
  run_case fleet_absent "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "without a fleet list the plugin stage is skipped, loudly" \
  "cloud-bootstrap: no fleet plugin list in this snapshot; plugin install skipped"
refute "and nothing is installed off the settings block alone" \
  "newly installed"
refute "and the skip is not misreported as a missing CLI or jq" \
  "claude CLI or jq unavailable"

CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true}}' \
  CASE_FLEET='not json at all' \
  run_case fleet_malformed "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a malformed fleet list skips the stage, it does not degrade to the settings block" \
  "is not a settings-shaped object; plugin install skipped"
refute "and installs nothing" "newly installed"

CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true}}' \
  CASE_FLEET='{"enabledPlugins":["alpha@melodic-software"]}' \
  run_case fleet_wrong_shape "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a wrong-shaped fleet list skips the stage" \
  "is not a settings-shaped object; plugin install skipped"
refute "and installs nothing" "newly installed"

CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true}}' \
  CASE_FLEET='[]' \
  run_case fleet_array "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a fleet list that is a bare array skips the stage" \
  "is not a settings-shaped object; plugin install skipped"
refute "and installs nothing" "newly installed"

REG_ALPHA_CLONE='{"plugins":{
  "alpha@melodic-software":[{"scope":"user","gitCommitSha":"@CLONE@"}],
  "beta@melodic-software":[{"scope":"user","gitCommitSha":"@HEAD@"}]}}'

CASE_CLONE=behind \
  run_case github_branch_ahead "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_FIRST" NONE
expect "a branch ahead of the marketplace clone is healthy against the clone, not stale against itself" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"
expect "and the block names the clone the session actually serves" \
  "is registered from github at"
expect "and brings the clone current first" \
  "calls: plugin marketplace update melodic-software"
refute "and no plugin is called stale" \
  "failed verification"
refute "and a pull that worked is not reported as failed" \
  "could not bring the melodic-software marketplace clone current"

CASE_CLONE=behind CASE_UPDATE_FAILS=1 \
  run_case github_update_fails "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_FIRST" NONE
expect "a failed marketplace pull is surfaced, not swallowed" \
  "could not bring the melodic-software marketplace clone current (\`plugin marketplace update\` failed); verifying against the clone as it stands"
expect "and the verdict is still measured against the clone as it stands" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"

CASE_CLONE=behind CASE_SOURCE_SHAPE=object \
  run_case github_nested_source "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_FIRST" NONE
expect "a nested source object still yields a one-line warning naming the repo" \
  "is registered from melodic-software/claude-code-plugins at"
expect "and the verdict is unchanged" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"

CASE_CLONE=ahead \
  run_case github_clone_ahead "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" "$REG_ALPHA_CLONE"
expect "a reinstall from a clone ahead of the checkout counts as refreshed, not failed" \
  "plugins 2 declared, 0 newly installed, 1 refreshed, 0 failed"
refute "and a plugin whose directory the clone did not change is not refreshed" \
  "beta@melodic-software failed verification"

CASE_CLONE=self \
  run_case directory_source "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a marketplace whose location is the checkout keeps the checkout as the reference" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"
refute "with no warning about a foreign clone" \
  "is registered from"
refute "and no marketplace update" \
  "marketplace update"

echo
echo "PASS=$pass FAIL=$fail"
if [[ "$fail" -ne 0 ]]; then
  echo "FAIL: .claude/cloud-bootstrap.sh plugin accounting contract broken" >&2
  exit 1
fi
echo "All cloud-bootstrap plugin accounting checks passed."
