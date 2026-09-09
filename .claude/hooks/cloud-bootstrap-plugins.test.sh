#!/usr/bin/env bash
# Contract test for the plugin accounting in .claude/cloud-bootstrap.sh: the
# block that installs/refreshes this repo's own catalog on a cloud VM and prints
# `cloud-bootstrap: plugins N declared, X newly installed, Y refreshed, Z failed`.
#
# That summary is the ONLY health signal a cloud session start emits for
# plugins, and it has failed in both directions. It over-reported first: the
# refresh chain was `uninstall && install && enable`, and `claude plugin install
# --scope user` already leaves the plugin enabled, so the trailing `enable`
# exits 1 with `Plugin "<id>" is already enabled at user scope` on every HEALTHY
# refresh (measured on claude 2.1.246). Startup lines read `65 failed` of 66
# refreshes while every one of those plugins was in fact reinstalled at HEAD.
# Then it under-reported: verifying only the plugins a run had touched left five
# genuinely broken end states printing `0 failed`, because the plugins most
# likely to be wrong are exactly the ones the run decided to skip.
#
# So the cases below pin BOTH directions. A healthy outcome must not be counted
# as a failure, and each broken end state must be named and counted.
#
# WHY IT LIVES IN .claude/hooks/. cloud-bootstrap.sh is the SessionStart hook
# .claude/settings.json registers, and this directory is a CI discovery root:
# `scripts/run-plugin-tests.sh` and `scripts/check-discriminating-test-skips.sh`
# both enumerate `find plugins .claude/hooks -type f -name '*.test.sh'`, so this
# suite runs on every push with no workflow change. A sibling
# `.claude/cloud-bootstrap.test.sh` would sit outside both roots and outside
# ci.yml's named `scripts/*.test.sh` steps, and would therefore never run.
#
# HOW IT DRIVES THE SCRIPT. cloud-bootstrap.sh is a linear provisioning script
# whose earlier steps install Node, run `npm ci` and pip-install hash-locked CI
# deps, none of which belong in a unit test. The plugin block is extracted by
# its two surrounding anchors (`claude_bin=` and the Python CI deps banner) and
# run on its own against a stub `claude` CLI plus synthetic
# `installed_plugins.json` fixtures.
#
# THE TRAILING ANCHOR IS THE DANGEROUS ONE, and it needs a guard of its own
# rather than the content checks that cover the leading one. The extractor is
# `awk '/^claude_bin=/ {p=1} /^# --- Python CI deps/ {p=0} p'`, so a leading
# anchor that moves yields nothing and every content check below fires. A
# TRAILING anchor that moves silently sets no stop: `p` stays 1 to end of file,
# extraction grows from ~191 lines to the whole tail of the script, and all
# three content checks still pass because the plugin block is still in there.
# The suite would keep reporting green while each of the thirteen cases below
# actually ran `python3 -m pip install --require-hashes`, `curl`ed release
# assets over the network, `install -m 0755`'d them into ~/.local/bin, and ran
# `git fetch --unshallow` against the fixture repo. So the end anchor is
# asserted to EXIST before extraction, and the extracted text is asserted NOT
# to contain `pip install` afterwards: the first check names the breakage, the
# second is the backstop that catches any other way the region could run long.
#
# Runner: scripts/run-plugin-tests.sh; also runnable directly:
#   bash .claude/hooks/cloud-bootstrap-plugins.test.sh
# Set CLOUD_BOOTSTRAP_SCRIPT to point the extraction at another copy of the
# script (used to confirm these cases fail against the pre-fix versions).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
# Clears GIT_DIR/GIT_WORK_TREE/GIT_CONFIG and friends, so the fixture repos
# below cannot write their throwaway identity into the caller's checkout.
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- extract the block under test -------------------------------------------
extract_fail=0

# Checked BEFORE extracting: awk sets no stop condition for an anchor that is
# not there, so a missing end anchor cannot be detected from the output.
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
# The backstop for an end anchor that exists but no longer terminates the
# region. Anything from a later section is out of bounds, and the hash-locked
# pip install is the first and loudest of them.
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

# --- harness -----------------------------------------------------------------
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
# The real shape on a cloud VM: the harness installs at project scope and the
# bootstrap at user scope, so every id appears twice.
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
# A 40-hex sha no clone contains: the force-push / shallow-fetch shape.
REG_BETA_UNKNOWN='{"plugins":{
  "alpha@melodic-software":[{"scope":"user","gitCommitSha":"@HEAD@"}],
  "beta@melodic-software":[{"scope":"user","gitCommitSha":"0123456789abcdef0123456789abcdef01234567"}]}}'

# run_case <name> <list-before> <list-after> <registry|MISSING> <registry-after|NONE>
# Builds a throwaway repo whose plugins/alpha changed between the first commit
# and HEAD while plugins/beta did not, runs the extracted block against a stub
# CLI, and leaves the combined output in $OUT.
#
# It also asserts the block's own EXIT STATUS is 0, in every case, healthy or
# not. That is not a formality: this block is a middle section of a script
# running under `set -euo pipefail`, so a nonzero exit here does not merely get
# the plugin count wrong, it aborts the whole cloud bootstrap before the Python
# CI deps install, the hygiene binaries and the session PATH export. A plugin
# that failed to install is best-effort by design and must still leave status
# 0; the summary line is how it reports, not the exit code.
OUT=""
RC=0
run_case() {
  local name="$1" before="$2" after="$3" registry="$4" registry_after="$5"
  local fx="$TMP/$name"
  mkdir -p "$fx/.claude" "$fx/node_modules/.bin" "$fx/plugins/alpha" "$fx/plugins/beta" "$fx/cfg/plugins"

  local default_settings='{"enabledPlugins":{"alpha@melodic-software":true,"beta@melodic-software":true}}'
  printf '%s\n' "${CASE_SETTINGS:-$default_settings}" >"$fx/.claude/settings.json"
  # A fleet list for the case, handed to the block through its test seam. The
  # default points at a path that does not exist, so the settings file stays
  # the only source, as on a machine outside the managed environment, and no
  # case ever reads a real /opt or /tmp list from the host.
  local fleet_env=(CLOUD_BOOTSTRAP_FLEET_LIST="$fx/no-fleet-list.json")
  if [[ -n "${CASE_FLEET:-}" ]]; then
    printf '%s\n' "$CASE_FLEET" >"$fx/fleet.json"
    fleet_env=(CLOUD_BOOTSTRAP_FLEET_LIST="$fx/fleet.json")
  fi
  # The catalog the block reads for `defaultEnabled`. Absent by default, which
  # is the pre-existing shape every case below was written against: no catalog
  # means no default-disabled ids, so disabled stays a failure.
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

  # The marketplace the stub reports. Absent by default (the pre-existing
  # shape: a name and nothing else, so the checkout stays the reference).
  # CASE_CLONE builds a clone of the fixture and reports it as a GitHub-sourced
  # marketplace's install location: `behind` leaves the clone at the first
  # commit (a branch that changed a plugin, main untouched), `ahead` adds a
  # third commit to the clone that changes plugins/alpha again (main moved),
  # `self` reports the checkout itself (the directory-source shape).
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
    # `plugin marketplace list --json` reports `source` as a plain string
    # (claude 2.1.263); CASE_SOURCE_SHAPE=object reports the nested object
    # known_marketplaces.json carries, which `jq -r` would pretty-print over
    # several lines if the block read it naively.
    if [[ "${CASE_SOURCE_SHAPE:-}" == object ]]; then
      printf '[{"name":"melodic-software","source":{"source":"github","repo":"melodic-software/claude-code-plugins"},"installLocation":"%s"}]\n' "$location" \
        >"$fx/marketplace-entry.json"
    else
      printf '[{"name":"melodic-software","source":"github","installLocation":"%s"}]\n' "$location" \
        >"$fx/marketplace-entry.json"
    fi
    # CASE_UPDATE_FAILS makes the stub's `marketplace update` exit 1: the
    # no-network / refused-fast-forward shape.
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

  # Stub CLI. Mutations are no-ops unless registry-after.json exists, so only
  # the block's own end-state verification can decide anything. `plugin enable`
  # exits 1 to reproduce the real "already enabled at user scope" status.
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
  [[ -f "$fx/update-fails" ]] && exit 1
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
  # The stub's mutation log rides along so a case can assert which CLI
  # mutations the block asked for, not only what it printed.
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

# --- healthy end states must not be counted as failures ----------------------

run_case steady "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a settled catalog reports no work and no failures" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"

run_case duplicated "$BOTH_DUPLICATED" "$BOTH_DUPLICATED" "$REG_BOTH_HEAD" NONE
expect "the real project+user duplicate listing passes" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 0 failed"

run_case fresh "$NONE" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a first-run install counts as installed, not failed" \
  "plugins 2 declared, 2 newly installed, 0 refreshed, 0 failed"

# The regression this whole change set exists for: the refresh chain's trailing
# `plugin enable` exits 1 on the healthy path, and the stub reproduces that.
run_case refreshed "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_FIRST" "$REG_BOTH_HEAD"
expect "a healthy refresh is not a failure even though \`plugin enable\` exits 1" \
  "plugins 2 declared, 0 newly installed, 1 refreshed, 0 failed"

# --- broken end states must be named and counted -----------------------------

run_case project_only "$BETA_PROJECT_ONLY" "$BETA_PROJECT_ONLY" "$REG_BOTH_HEAD" NONE
expect "a plugin present only at project scope is a failure" \
  "beta@melodic-software failed verification after no action: not installed at user scope"
expect "and is named in the summary" \
  "0 refreshed, 1 failed: beta@melodic-software"

run_case disabled "$BETA_DISABLED" "$BETA_DISABLED" "$REG_BOTH_HEAD" NONE
expect "a plugin installed at user scope but disabled is a failure" \
  "beta@melodic-software failed verification after no action: installed at user scope but not enabled"

# --- a catalog `defaultEnabled: false` makes disabled the EXPECTED end state --
# The fleet list and the settings block answer INSTALL; the catalog owns
# enablement, and `plugin install --scope user -y` honours it (claude 2.1.263:
# exit 0, "This plugin is disabled by default", `plugin list --json` reporting
# scope=user with enabled=false). Scoring that as a failed install put a
# standing nonzero failure count in every fresh snapshot's log. The pair below
# is the point: the SAME disabled end state passes with the catalog entry and
# fails without it, which pins the discriminator on the catalog rather than on
# the disabled state.

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

# Still held to the other two checks, so the exception cannot hide a real break.
CASE_MARKETPLACE="$BETA_DEFAULT_DISABLED" \
  run_case default_disabled_project_only "$BETA_PROJECT_ONLY" "$BETA_PROJECT_ONLY" "$REG_BOTH_HEAD" NONE
expect "a catalog-disabled plugin missing from user scope is still a failure" \
  "beta@melodic-software failed verification after no action: not installed at user scope"

CASE_MARKETPLACE="$BETA_DEFAULT_DISABLED" \
  run_case default_disabled_stale "$BETA_DISABLED" "$BETA_DISABLED" "$REG_BETA_SHA_NULL" NONE
expect "a catalog-disabled plugin is still snapshot-verified" \
  "beta@melodic-software failed verification after no action: cannot verify snapshot: no user-scope gitCommitSha recorded"

# The exemption requires JSON boolean false. A string "false" is the same
# malformed-output class as the string "true" case below, even when the
# catalog marks the plugin default-disabled.
CASE_MARKETPLACE="$BETA_DEFAULT_DISABLED" \
  run_case default_disabled_enabled_string "$BETA_DISABLED_STRING" "$BETA_DISABLED_STRING" "$REG_BOTH_HEAD" NONE
expect "a catalog-disabled plugin with enabled as the string \"false\" still fails" \
  "beta@melodic-software failed verification after no action: installed at user scope but not enabled"

# --- broken end states must be named and counted, continued ------------------

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

# alpha's directory changed between the recorded commit and HEAD; beta's did
# not. Only alpha is stale, which pins the criterion as a per-plugin directory
# diff rather than "recorded sha differs from HEAD".
run_case stale_refresh_stuck "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_FIRST" NONE
expect "a refresh that did not take is reported with the directory that changed" \
  "alpha@melodic-software failed verification after refresh: plugins/alpha changed between the installed commit"
refute "and a plugin whose own directory did not change is not called stale" \
  "beta@melodic-software failed verification"
# The only case where a plugin was ATTEMPTED and then failed, so it is the only
# one that can catch an id credited to `refreshed` (or `installed`) and to
# `failed` at the same time. The counts must partition, not overlap.
expect "an attempted plugin that failed is counted once, as failed only" \
  "plugins 2 declared, 0 newly installed, 0 refreshed, 1 failed: alpha@melodic-software"

run_case unreadable "$BOTH_USER" 'not json at all' "$REG_BOTH_HEAD" NONE
expect "an unreadable plugin list fails the whole batch" \
  "none could be verified, see the warning above"
expect "with one warning for the batch" \
  "could not read \`claude plugin list --json\`; no plugin could be verified"
refute "and no per-plugin flood" \
  "failed verification after"

# --- the fleet list baked into the snapshot is a source too -------------------
# The shared environment writes the fleet plugin list into the snapshot; a
# settings block reduced to deltas must still enable the fleet's entries for
# this marketplace, a settings false must opt out of a fleet entry, and other
# marketplaces' fleet entries are out of scope here.

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
  run_case fleet_absent "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "without a fleet list the settings block is the only source" \
  "plugins 1 declared, 0 newly installed, 0 refreshed, 0 failed"

CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true}}' \
  CASE_FLEET='not json at all' \
  run_case fleet_malformed "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a malformed fleet list degrades to the settings block, not to an empty set" \
  "plugins 1 declared, 0 newly installed, 0 refreshed, 0 failed"

# Valid JSON of the wrong shape (an error body, an array where the object
# should be) would break the merge the same way a parse failure does.
CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true}}' \
  CASE_FLEET='{"enabledPlugins":["alpha@melodic-software"]}' \
  run_case fleet_wrong_shape "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a wrong-shaped fleet list degrades to the settings block, not to an empty set" \
  "plugins 1 declared, 0 newly installed, 0 refreshed, 0 failed"

CASE_SETTINGS='{"enabledPlugins":{"alpha@melodic-software":true}}' \
  CASE_FLEET='[]' \
  run_case fleet_array "$BOTH_USER" "$BOTH_USER" "$REG_BOTH_HEAD" NONE
expect "a fleet list that is a bare array degrades to the settings block" \
  "plugins 1 declared, 0 newly installed, 0 refreshed, 0 failed"

# --- the marketplace a snapshot pre-registers is not this checkout -----------
# A cloud snapshot arrives with a marketplace of this name registered from
# GitHub, so the checkout is never registered and every install resolves
# against that clone, which records ITS commit as gitCommitSha. The reference
# for the refresh decision and the verification is therefore the clone, not
# the checkout, and the block says so once. Three shapes: the clone behind the
# checkout (a branch that changed a plugin, main untouched), the clone ahead of
# it (main moved while the checkout stayed), and a location that IS the
# checkout (the directory-source shape, whose behaviour must not change).

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

# The pull can fail (no network, a clone the CLI refuses to fast-forward).
# The clone as it stands is still what the installs serve, so the verdict
# stays truthful about serving; what the block may not do is claim currency
# or swallow the failure.
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

# --- report -------------------------------------------------------------------
echo
echo "PASS=$pass FAIL=$fail"
if [[ "$fail" -ne 0 ]]; then
  echo "FAIL: .claude/cloud-bootstrap.sh plugin accounting contract broken" >&2
  exit 1
fi
echo "All cloud-bootstrap plugin accounting checks passed."
