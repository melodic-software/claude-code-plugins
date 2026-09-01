#!/usr/bin/env bash
# Black-box contract test for the check-only carve-out assertions in
# validate-plugin-contracts.mjs.
#
# Self-contained: builds a throwaway plugins/ tree plus a fixture
# config-cascade registry in an mktemp dir and runs the real validator with
# that dir as cwd, which is the only root the validator knows (it reads
# process.cwd() and resolves nothing relative to its own location, so no copy
# of the script is needed). Mutates only its own mktemp dir.
#
# A green run on the current repo tree is not evidence these assertions work:
# no shipping plugin violates them. The fixtures below prove the gate goes red
# on the four failure classes #3137 named -- a plugin taking the carve-out
# while owning a registered tracked-config surface, a carve-out-shaped skill
# that never declares the carve-out, a userConfig-only claim from a manifest
# declaring no userConfig, and a registry the gate can no longer read -- and
# the paired inverses prove it stays green for the two conforming shapes.
#
# A fixture root always trips the unrelated repo-wide checks (the shared
# lifecycle artifact protocol and its five plugin copies), so every assertion
# here is on the presence or absence of a SPECIFIC failure line, never on the
# aggregate exit code. The one exit-code assertion is the closing real-corpus
# case.
#
# Bespoke PASS/FAIL counters by design, not drift: this is repo tooling, not a
# plugin, so no plugin assertion library applies here -- see
# docs/conventions/shell-test-helpers/README.md.
# shellcheck disable=SC2016  # fixture rows are literal markdown; the backticks they carry are content, never expansion
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/validate-plugin-contracts.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not on PATH; the validator cannot be exercised" >&2
  exit 2
fi

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OWNS_TRACKED_CONFIG='the check-only carve-out is unavailable here'
NO_DECLARATION='must declare the check-only carve-out it relies on'
NO_USER_CONFIG='requires the plugin manifest to declare userConfig'
NO_DOCUMENTED_APPLY='must document the apply action'
REGISTRY_MISSING='the consumer-config registry is required'
REGISTRY_UNSTRUCTURED='must carry an "## Implementers" section'
REGISTRY_EMPTY='named no surfaces'

# fail() prints `- <path>: <message>`. A warn-only path would still contain
# the message substring but would not carry the leading `- ` bullet.
has_fail_line() {
  local needle="$1"
  grep -qE "^- .*: .*${needle}" <<<"$out"
}

reset_fixture() {
  rm -rf "$TMP/plugins" "$TMP/docs"
  mkdir -p "$TMP/plugins"
  write_registry
}

# write_registry [surface ...] -- the Implementers table the validator reads as
# the set of plugins owning a tracked consumer config surface. Called with no
# arguments it still carries one unrelated row, so an empty table is only ever
# asserted deliberately.
write_registry() {
  mkdir -p "$TMP/docs/conventions/config-cascade"
  {
    echo '# Consumer config cascade (fixture)'
    echo
    echo '## Deviations'
    echo
    echo '| Surface | Note |'
    echo '|---|---|'
    echo '| `not-an-implementer` | a row outside the Implementers table |'
    echo
    echo '## Implementers'
    echo
    echo '| Surface | Consumer config path | Layers | Conformance |'
    echo '|---|---|---|---|'
    local surface
    for surface in "$@"; do
      printf '| `%s` | `.claude/%s.md` | all three | conforms |\n' "$surface" "$surface"
    done
    echo
    echo '### Overlay spelling drift'
    echo
    echo 'Prose after the table.'
  } >"$TMP/docs/conventions/config-cascade/README.md"
}

# make_plugin <name> <user-config-keys> -- an empty string declares no
# userConfig at all.
make_plugin() {
  local plugin="$1" keys="$2" user_config='' key first=1
  mkdir -p "$TMP/plugins/$plugin/.claude-plugin"
  if [[ -n "$keys" ]]; then
    for key in $keys; do
      if ((first)); then first=0; else user_config="$user_config, "; fi
      user_config="$user_config\"$key\": {\"type\": \"string\", \"title\": \"$key\"}"
    done
    user_config=", \"userConfig\": {$user_config}"
  fi
  printf '{"name": "%s", "version": "0.1.0", "description": "fixture"%s}\n' \
    "$plugin" "$user_config" >"$TMP/plugins/$plugin/.claude-plugin/plugin.json"
}

# write_setup_skill <plugin> <argument-hint> -- body arrives on stdin.
write_setup_skill() {
  local plugin="$1" hint="$2"
  mkdir -p "$TMP/plugins/$plugin/skills/setup"
  {
    echo '---'
    printf 'description: "Fixture setup skill for %s."\n' "$plugin"
    printf 'argument-hint: "%s"\n' "$hint"
    echo 'user-invocable: true'
    echo 'disable-model-invocation: true'
    echo '---'
    echo
    cat
  } >"$TMP/plugins/$plugin/skills/setup/SKILL.md"
}

# The conforming carve-out body: check-only, naming the native userConfig
# surface, exactly as the five shipping carve-out skills word it.
carve_out_body() {
  cat <<'BODY'
## Purpose

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's entire
configuration surface is native `userConfig`, so `check` (the default and only action) verifies
and reports, and reconfiguration routes through Claude Code's native flow.
BODY
}

run_fixture() { (cd "$TMP" && node "$SUT" 2>&1); }

# --- 1. Conforming carve-out: no apply, declares it, userConfig-backed, not a
#        registered tracked-config owner -> no carve-out failure. ------------
reset_fixture
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha check
out="$(run_fixture)"
if grep -q "$OWNS_TRACKED_CONFIG" <<<"$out" ||
  grep -q "$NO_DECLARATION" <<<"$out" ||
  grep -q "$NO_USER_CONFIG" <<<"$out"; then
  fail "a conforming userConfig-only carve-out should raise no carve-out failure: $out"
else
  pass "a conforming userConfig-only carve-out passes the carve-out assertions"
fi

# --- 2. #3137's own failure class: the same skill, but the plugin owns a
#        tracked consumer config surface the registry records. ---------------
reset_fixture
write_registry alpha
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha check
out="$(run_fixture)"
if has_fail_line "$OWNS_TRACKED_CONFIG" &&
  grep -q 'narrow-write shape' <<<"$out" &&
  grep -qE 'alpha[/\\]skills[/\\]setup[/\\]SKILL\.md' <<<"$out"; then
  pass "a carve-out claim from a plugin owning tracked consumer config fails the gate"
else
  fail "a registered tracked-config owner should not reach the carve-out: $out"
fi

# --- 2b. The registry names a surface whose owning plugin is listed alongside
#         it, the shape the shipping "`standards` (`planning`, `review`)" row
#         takes. Every backticked token in the cell is an owner. -------------
reset_fixture
mkdir -p "$TMP/docs/conventions/config-cascade"
{
  echo '# Consumer config cascade (fixture)'
  echo
  echo '## Implementers'
  echo
  echo '| Surface | Consumer config path | Layers | Conformance |'
  echo '|---|---|---|---|'
  echo '| `a-shared-surface` (`alpha`, `gamma`) | `.claude/shared.yaml` | all three | conforms |'
} >"$TMP/docs/conventions/config-cascade/README.md"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha check
out="$(run_fixture)"
if has_fail_line "$OWNS_TRACKED_CONFIG"; then
  pass "a plugin named alongside the surface it co-owns is read out of the registry row"
else
  fail "a co-owner named in the surface cell should not reach the carve-out: $out"
fi

# --- 3. Mentioning apply in prose is not a carve-out declaration:
#        a carve-out-shaped skill whose body only mentions apply in prose. ---
reset_fixture
make_plugin alpha alpha_api_key
write_setup_skill alpha check <<'BODY'
## Purpose

`check` reports readiness. There is no `apply` action here.
BODY
out="$(run_fixture)"
if has_fail_line "$NO_DECLARATION"; then
  pass "a skill offering no apply must declare the carve-out, not merely mention apply"
else
  fail "an undeclared carve-out shape should fail the gate: $out"
fi

# --- 3b. Advertising apply in argument-hint without documenting it. --------
reset_fixture
write_registry alpha
make_plugin alpha alpha_api_key
write_setup_skill alpha 'check | apply' <<'BODY'
## Purpose

Check-only under the native `userConfig` surface: `check` reports readiness.
There is no apply action here.
BODY
out="$(run_fixture)"
if has_fail_line "$NO_DOCUMENTED_APPLY"; then
  pass "advertising apply without documenting it fails the gate"
else
  fail "an advertised-but-undocumented apply should fail the gate: $out"
fi

# --- 4. A userConfig-only claim the manifest does not back. -----------------
reset_fixture
make_plugin alpha ''
carve_out_body | write_setup_skill alpha check
out="$(run_fixture)"
if has_fail_line "$NO_USER_CONFIG"; then
  pass "claiming the userConfig-only carve-out with no declared userConfig fails the gate"
else
  fail "an unbacked userConfig-only claim should fail the gate: $out"
fi

# --- 4b. The same gap under the doctrine's own wording, not the one phrase. -
reset_fixture
make_plugin alpha ''
write_setup_skill alpha check <<'BODY'
## Purpose

Check-only under the native `userConfig` surface: `check` reports readiness.
BODY
out="$(run_fixture)"
if has_fail_line "$NO_USER_CONFIG"; then
  pass "doctrine wording that names userConfig without a manifest declaration fails the gate"
else
  fail "a native-userConfig-surface claim with no userConfig should fail: $out"
fi

# --- 4c. A check-only skill that names userConfig only to deny it. ----------
reset_fixture
make_plugin alpha ''
write_setup_skill alpha check <<'BODY'
## Purpose

Check-only: this plugin has no `userConfig`. `check` reports external prerequisites.
BODY
out="$(run_fixture)"
if grep -q "$NO_USER_CONFIG" <<<"$out"; then
  fail "denying userConfig should not be read as claiming the surface: $out"
else
  pass "a check-only skill that says it has no userConfig is not an unbacked claim"
fi

# --- 5. Inverse: the narrow-write shape is untouched by the carve-out
#        assertions, even for a registered tracked-config owner. -------------
reset_fixture
write_registry beta
make_plugin beta ''
write_setup_skill beta 'check | apply [remove]' <<'BODY'
## Purpose

`check` reports drift; `apply` converges this plugin's tracked project config. Every surface it
may not write is handled the check-only way instead.
BODY
out="$(run_fixture)"
if grep -q "$OWNS_TRACKED_CONFIG" <<<"$out" ||
  grep -q "$NO_DECLARATION" <<<"$out" ||
  grep -q "$NO_USER_CONFIG" <<<"$out"; then
  fail "a narrow-write setup skill should raise no carve-out failure: $out"
else
  pass "a narrow-write setup skill owning tracked config passes the carve-out assertions"
fi

# --- 6. The registry is an input, so losing it fails loudly rather than
#        degrading the carve-out check into a no-op. -------------------------
reset_fixture
rm -rf "$TMP/docs"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha check
out="$(run_fixture)"
if has_fail_line "$REGISTRY_MISSING"; then
  pass "a missing consumer-config registry fails the gate"
else
  fail "a missing registry should fail rather than silently skip: $out"
fi

# --- 7. Present but restructured: the Implementers section is gone. ---------
reset_fixture
mkdir -p "$TMP/docs/conventions/config-cascade"
printf '# Consumer config cascade (fixture)\n\nNo Implementers section here.\n' \
  >"$TMP/docs/conventions/config-cascade/README.md"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha check
out="$(run_fixture)"
if has_fail_line "$REGISTRY_UNSTRUCTURED"; then
  pass "a registry with no Implementers section fails the gate"
else
  fail "a restructured registry should fail rather than silently skip: $out"
fi

# --- 8. Present and structured, but the table names nothing. ----------------
reset_fixture
write_registry
# Drop the one unrelated row's section so the Implementers table is genuinely
# empty rather than merely narrow.
mkdir -p "$TMP/docs/conventions/config-cascade"
{
  echo '# Consumer config cascade (fixture)'
  echo
  echo '## Implementers'
  echo
  echo '| Surface | Consumer config path | Layers | Conformance |'
  echo '|---|---|---|---|'
} >"$TMP/docs/conventions/config-cascade/README.md"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha check
out="$(run_fixture)"
if has_fail_line "$REGISTRY_EMPTY"; then
  pass "an Implementers table naming no surfaces fails the gate"
else
  fail "an empty registry table should fail rather than silently skip: $out"
fi

# ===========================================================================
# Retired-conventions manifests (plugins/<plugin>/retirements.yaml).
#
# Same discipline: each case asserts one specific failure line. The fixture
# helper at plugins/claude-config/lib/check-retirements.sh is a placeholder;
# the validator checks only identity with the per-plugin copy, never content.
# ===========================================================================

R_UNKNOWN_KEY='unknown key "'
R_BAD_ENUM='"kind" must be one of file, dir, line'
R_LINE_NO_MATCH='"match" is required when kind is line'
R_BAD_PATH='"path" must be repo-relative'
R_DUP_ID='duplicate id "'
R_MIGRATE_NO_SUCCESSOR='action migrate requires "successor"'
R_HELPER_MISSING='a plugin shipping retirements.yaml must carry the synced helper'
R_HELPER_DRIFT='must remain byte-identical to plugins/claude-config/lib/check-retirements.sh'
R_CANONICAL_MISSING='it is the canonical helper every plugin shipping retirements.yaml syncs'
R_SETUP_NO_REF='must reference check-retirements.sh when the plugin ships retirements.yaml'
R_REF_NO_MANIFEST='but the plugin ships no retirements.yaml'
R_EVALS_MISSING='every retirement record needs an eval covering it'
R_EVAL_UNCOVERED='no eval covers retirement record "'
R_APPEND_ONLY='records are append-only; demote with `status: report-only` instead'
R_FIELD_CHANGED='changed since HEAD; records are append-only'
R_BASE_UNRESOLVED='does not resolve to a commit'
R_SKIPPED='VALIDATE_CONTRACTS_BASE_REF unset; retirements append-only check skipped'

# Every failure line the retirements section can emit, for the "none of them"
# assertion on the conforming fixture.
retirement_failure_lines() {
  grep -E "retirements\.yaml: |check-retirements\.sh|retirement record|ships no retirements" <<<"$out" | grep -E '^- ' || true
}

write_canonical_helper() {
  mkdir -p "$TMP/plugins/claude-config/lib"
  printf '#!/usr/bin/env bash\n# fixture placeholder for the canonical helper\nexit 0\n' \
    >"$TMP/plugins/claude-config/lib/check-retirements.sh"
}

# sync_helper <plugin> -- the per-plugin byte-identical copy.
sync_helper() {
  mkdir -p "$TMP/plugins/$1/lib"
  cp "$TMP/plugins/claude-config/lib/check-retirements.sh" "$TMP/plugins/$1/lib/check-retirements.sh"
}

# write_manifest <plugin> -- manifest body arrives on stdin.
write_manifest() {
  mkdir -p "$TMP/plugins/$1"
  cat >"$TMP/plugins/$1/retirements.yaml"
}

# write_evals <plugin> <id ...> -- one eval case naming every id given.
write_evals() {
  local plugin="$1"
  shift
  mkdir -p "$TMP/plugins/$plugin/skills/setup/evals"
  {
    echo '{"skill_name": "setup", "evals": [{"id": 1, "name": "detects-and-cleans-retired-artifacts",'
    printf '"prompt": "/%s:setup check", "expected_output": "Reports each retirement hit, then a clean re-run.",\n' "$plugin"
    echo '"files": [], "expectations": ['
    local id first=1
    for id in "$@"; do
      if ((first)); then first=0; else echo ','; fi
      printf '"Detects %s on the hit path and reports clean after apply"' "$id"
    done
    echo ']}]}'
  } >"$TMP/plugins/$plugin/skills/setup/evals/evals.json"
}

retiring_setup_body() {
  cat <<'BODY'
## Purpose

`check` reports drift, running `lib/check-retirements.sh` against the consumer repo as one fixed
step; `apply` converges this plugin's tracked project config and cleans retired artifacts per record.
BODY
}

valid_manifest() {
  cat <<'YAML'
# Retired conventions for alpha.
---
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: line
path: .gitignore
match: '^\.claude/alpha-cache/?$'
action: remove-line
note: the cache dir moved under the plugin data dir
---
id: alpha-r002
retired: "2026-08-15"
plugin_version: "1.5.0"
kind: file
path: .claude/alpha.json
content_match: "\"schema\": *\"v1\""
action: migrate
successor: "the v1 keys now live in .claude/alpha.md under the Settings heading"
note: "config file replaced by a convention doc"
status: report-only
YAML
}

# The full conforming shape: manifest + synced helper + referencing setup
# skill + evals naming both ids.
conforming_retirements_fixture() {
  reset_fixture
  write_canonical_helper
  make_plugin alpha ''
  retiring_setup_body | write_setup_skill alpha 'check | apply'
  valid_manifest | write_manifest alpha
  sync_helper alpha
  write_evals alpha alpha-r001 alpha-r002
}

# --- R1. Conforming manifest raises none of the retirements failures. -------
conforming_retirements_fixture
out="$(run_fixture)"
if [[ -z "$(retirement_failure_lines)" ]] && grep -q "$R_SKIPPED" <<<"$out"; then
  pass "a conforming retirements manifest raises no retirements failure and reports the skipped append-only check"
else
  fail "a conforming retirements fixture should raise no retirements failure: $out"
fi

# --- R2. Malformed manifests, one rule each. --------------------------------
malformed_case() {
  local title="$1" needle="$2"
  conforming_retirements_fixture
  write_manifest alpha
  out="$(run_fixture)"
  if has_fail_line "$needle" && grep -qE 'alpha[/\\]retirements\.yaml' <<<"$out"; then
    pass "$title"
  else
    fail "$title -- expected a failure line containing '$needle': $out"
  fi
}

malformed_case "an unknown key fails the manifest" "$R_UNKNOWN_KEY" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: file
path: .claude/alpha.json
action: delete
note: one line
severity: high
YAML

malformed_case "a bad kind enum fails the manifest" "$R_BAD_ENUM" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: folder
path: .claude/alpha
action: delete
note: one line
YAML

malformed_case "a line record without match fails the manifest" "$R_LINE_NO_MATCH" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: line
path: .gitignore
action: remove-line
note: one line
YAML

malformed_case "a path with a .. segment fails the manifest" "$R_BAD_PATH" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: file
path: ../other-repo/.claude/alpha.json
action: delete
note: one line
YAML

malformed_case "a duplicate id fails the manifest" "$R_DUP_ID" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: file
path: .claude/alpha.json
action: delete
note: one line
---
id: alpha-r001
retired: 2026-08-02
plugin_version: 1.4.1
kind: dir
path: .claude/alpha
action: delete
note: one line
YAML

malformed_case "migrate without successor fails the manifest" "$R_MIGRATE_NO_SUCCESSOR" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: file
path: .claude/alpha.json
action: migrate
note: one line
YAML

# --- R3. Helper copy missing. -----------------------------------------------
conforming_retirements_fixture
rm "$TMP/plugins/alpha/lib/check-retirements.sh"
out="$(run_fixture)"
if has_fail_line "$R_HELPER_MISSING"; then
  pass "a manifest with no synced helper copy fails the gate"
else
  fail "a missing helper copy should fail: $out"
fi

# --- R3b. Helper copy drifted by one byte. ----------------------------------
conforming_retirements_fixture
printf '\n' >>"$TMP/plugins/alpha/lib/check-retirements.sh"
out="$(run_fixture)"
if has_fail_line "$R_HELPER_DRIFT"; then
  pass "a helper copy that differs by one byte fails the gate"
else
  fail "a drifted helper copy should fail: $out"
fi

# --- R3c. The canonical helper itself is gone. ------------------------------
conforming_retirements_fixture
rm "$TMP/plugins/claude-config/lib/check-retirements.sh"
out="$(run_fixture)"
if has_fail_line "$R_CANONICAL_MISSING"; then
  pass "a missing canonical helper fails once by name"
else
  fail "a missing canonical helper should fail: $out"
fi

# --- R4. Setup skill does not reference the helper. -------------------------
conforming_retirements_fixture
write_setup_skill alpha 'check | apply' <<'BODY'
## Purpose

`check` reports drift; `apply` converges this plugin's tracked project config.
BODY
out="$(run_fixture)"
if has_fail_line "$R_SETUP_NO_REF"; then
  pass "a retiring plugin whose setup skill never runs the helper fails the gate"
else
  fail "a setup skill not referencing the helper should fail: $out"
fi

# --- R5. Inverse wiring: helper referenced, no manifest. --------------------
reset_fixture
write_canonical_helper
make_plugin beta ''
retiring_setup_body | write_setup_skill beta 'check | apply'
out="$(run_fixture)"
if has_fail_line "$R_REF_NO_MANIFEST" && grep -qE 'beta[/\\]skills[/\\]setup[/\\]SKILL\.md' <<<"$out"; then
  pass "a setup skill referencing the helper with no manifest fails the gate"
else
  fail "a dangling helper reference should fail: $out"
fi

# --- R5b. Inverse wiring: helper copy carried, no manifest. -----------------
reset_fixture
write_canonical_helper
make_plugin beta ''
sync_helper beta
out="$(run_fixture)"
if has_fail_line "$R_REF_NO_MANIFEST" && grep -qE 'beta[/\\]lib[/\\]check-retirements\.sh' <<<"$out"; then
  pass "a helper copy carried with no manifest fails the gate"
else
  fail "a dangling helper copy should fail: $out"
fi

# --- R5c. claude-config is the canonical home: its copy and reference stand
#          without a manifest. -----------------------------------------------
reset_fixture
write_canonical_helper
make_plugin claude-config ''
retiring_setup_body | write_setup_skill claude-config 'check | apply'
out="$(run_fixture)"
if grep -q "$R_REF_NO_MANIFEST" <<<"$out"; then
  fail "claude-config should be exempt from the inverse wiring check: $out"
else
  pass "claude-config carries the helper and references it without a manifest"
fi

# --- R6. Evals: one id uncovered; evals.json missing. -----------------------
conforming_retirements_fixture
write_evals alpha alpha-r001
out="$(run_fixture)"
if has_fail_line "${R_EVAL_UNCOVERED}alpha-r002" && ! grep -q "${R_EVAL_UNCOVERED}alpha-r001" <<<"$out"; then
  pass "an id no eval names fails by id, and a covered id does not"
else
  fail "an uncovered record id should fail by name: $out"
fi

conforming_retirements_fixture
rm -rf "$TMP/plugins/alpha/skills/setup/evals"
out="$(run_fixture)"
if has_fail_line "$R_EVALS_MISSING" && grep -q 'alpha-r001, alpha-r002' <<<"$out"; then
  pass "a missing evals.json fails naming every record id"
else
  fail "a missing evals.json should fail naming the ids: $out"
fi

# --- R7. Append-only against a git base. ------------------------------------
# The fixture root becomes its own repository: commit the conforming manifest,
# mutate the working tree, run with the base ref pointed at HEAD.
run_fixture_with_base() { (cd "$TMP" && VALIDATE_CONTRACTS_BASE_REF="$1" node "$SUT" 2>&1); }
fixture_git() { git -C "$TMP" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
commit_fixture() {
  rm -rf "$TMP/.git"
  fixture_git init -q
  fixture_git add -A
  fixture_git commit -q -m fixture
}

# A record deleted since base.
conforming_retirements_fixture
commit_fixture
valid_manifest | sed '/^id: alpha-r002$/,$d' | write_manifest alpha
out="$(run_fixture_with_base HEAD)"
if has_fail_line "$R_APPEND_ONLY" && grep -q 'record "alpha-r002"' <<<"$out"; then
  pass "deleting a merged record fails the append-only check by id"
else
  fail "a deleted record should fail append-only: $out"
fi

# A frozen field rewritten on an existing id.
conforming_retirements_fixture
commit_fixture
valid_manifest | sed 's|^path: \.gitignore$|path: .git-ignore|' | write_manifest alpha
out="$(run_fixture_with_base HEAD)"
if has_fail_line "$R_FIELD_CHANGED" && grep -q 'record "alpha-r001": "path" changed' <<<"$out"; then
  pass "rewriting a frozen field on a merged record fails naming the field"
else
  fail "a rewritten frozen field should fail naming it: $out"
fi

# The legal inverse: status flip plus a note fix, plus a brand-new record.
conforming_retirements_fixture
commit_fixture
{
  valid_manifest | sed -e 's|^status: report-only$|status: active|' -e 's|^note: the cache dir moved.*$|note: the cache dir moved under the plugin data dir (typo fixed)|'
  cat <<'YAML'
---
id: alpha-r003
retired: 2026-09-01
plugin_version: 1.6.0
kind: dir
path: .claude/alpha-tmp
action: delete
note: scratch dir no longer used
YAML
} | write_manifest alpha
write_evals alpha alpha-r001 alpha-r002 alpha-r003
out="$(run_fixture_with_base HEAD)"
if grep -q 'append-only' <<<"$out" || grep -q "$R_SKIPPED" <<<"$out"; then
  fail "a status flip, note fix, and appended record should pass append-only and not report it skipped: $out"
else
  pass "a status flip, a note fix, and an appended record pass the append-only check"
fi

# The whole manifest deleted since base.
conforming_retirements_fixture
commit_fixture
rm "$TMP/plugins/alpha/retirements.yaml"
out="$(run_fixture_with_base HEAD)"
if has_fail_line "$R_APPEND_ONLY" && grep -q 'plugins/alpha/retirements.yaml: was present at HEAD' <<<"$out"; then
  pass "deleting a whole merged manifest fails the append-only check"
else
  fail "a deleted manifest should fail append-only: $out"
fi

# A base ref that does not resolve fails rather than skipping. This failure is
# global, not tied to a file, so its line has no `path: ` prefix.
conforming_retirements_fixture
commit_fixture
out="$(run_fixture_with_base no-such-ref)"
if grep -qE "^- .*${R_BASE_UNRESOLVED}" <<<"$out"; then
  pass "an unresolvable base ref fails loudly instead of skipping"
else
  fail "an unresolvable base ref should fail: $out"
fi
rm -rf "$TMP/.git"

# --- 9. Real corpus: every shipping setup skill still conforms. -------------
out="$( (cd "$REPO_ROOT" && node "$SUT" 2>&1))"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "the shipping plugins/ tree still validates end to end"
else
  fail "the shipping tree should stay green (rc=$rc): $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
