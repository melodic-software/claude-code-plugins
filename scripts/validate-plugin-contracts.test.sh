#!/usr/bin/env bash
# test-scope: .claude-plugin/marketplace.json
# test-scope: plugins/*/retirements.yaml plugins/*/skills/*/evals/evals.json plugins/*/evals/*/case.yaml plugins/*/evals/*/prompt.md plugins/*/evals/*/graders/*.md plugins/*/reference/artifact-protocol.md
# shellcheck disable=SC2016  # fixture rows are literal markdown; the backticks they carry are content, never expansion
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/validate-plugin-contracts.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not on PATH; the validator cannot be exercised" >&2
  exit 2
fi

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TMP=""
fixture_tree::build TMP --label plugin-contracts

OWNS_TRACKED_CONFIG='the check-only carve-out is unavailable here'
NO_DECLARATION='must declare the check-only carve-out it relies on'
NO_USER_CONFIG='requires the plugin manifest to declare userConfig'
NO_DOCUMENTED_APPLY='must document the apply action'
REGISTRY_MISSING='the consumer-config registry is required'
REGISTRY_UNSTRUCTURED='must carry an "## Implementers" section'
REGISTRY_EMPTY='named no surfaces'

has_fail_line() {
  local needle="$1"
  grep -qE "^- .*: .*${needle}" <<<"$out"
}

reset_fixture() {
  rm -rf "$TMP/plugins" "$TMP/docs"
  mkdir -p "$TMP/plugins"
  write_registry
}

write_registry() {
  mkdir -p "$TMP/docs/contracts/config-cascade"
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
    echo '### Personal override spelling drift'
    echo
    echo 'Prose after the table.'
  } >"$TMP/docs/contracts/config-cascade/README.md"
}

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
  printf '{"version": "0.1.0",\n"name": "%s",\n"description": "fixture"%s}\n' \
    "$plugin" "$user_config" >"$TMP/plugins/$plugin/.claude-plugin/plugin.json"
}

write_setup_skill() {
  local plugin="$1" hint="$2" disabled="${3:-true}"
  mkdir -p "$TMP/plugins/$plugin/skills/setup"
  {
    echo '---'
    printf 'description: "Fixture setup skill for %s."\n' "$plugin"
    printf 'argument-hint: "%s"\n' "$hint"
    echo 'user-invocable: true'
    printf 'disable-model-invocation: %s\n' "$disabled"
    echo '---'
    echo
    cat
  } >"$TMP/plugins/$plugin/skills/setup/SKILL.md"
}

carve_out_body() {
  cat <<'BODY'
## Purpose

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's entire
configuration is native `userConfig`, so `check` (the default and only action) verifies
and reports, and reconfiguration routes through Claude Code's native flow.
BODY
}

run_fixture() { (cd "$TMP" && node "$SUT" 2>&1); }

reset_fixture
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha '[check]'
out="$(run_fixture)"
if grep -q "$OWNS_TRACKED_CONFIG" <<<"$out" ||
  grep -q "$NO_DECLARATION" <<<"$out" ||
  grep -q "$NO_USER_CONFIG" <<<"$out"; then
  fail "a conforming userConfig-only carve-out should raise no carve-out failure: $out"
else
  ok "a conforming userConfig-only carve-out passes the carve-out assertions"
fi

SETUP_NOT_DISABLED='setup skills must set disable-model-invocation: true'
for spelling in true yes YES on 1 'true # class (ii)'; do
  reset_fixture
  make_plugin alpha alpha_api_key
  carve_out_body | write_setup_skill alpha '[check]' "$spelling"
  out="$(run_fixture)"
  if grep -q "$SETUP_NOT_DISABLED" <<<"$out"; then
    fail "setup skill spelling '$spelling' should satisfy the gate: $out"
  else
    ok "setup skill spelling '$spelling' satisfies the gate"
  fi
done
for spelling in false no maybe '"true"'; do
  reset_fixture
  make_plugin alpha alpha_api_key
  carve_out_body | write_setup_skill alpha '[check]' "$spelling"
  out="$(run_fixture)"
  if has_fail_line "$SETUP_NOT_DISABLED"; then
    ok "setup skill spelling '$spelling' fails the gate"
  else
    fail "setup skill spelling '$spelling' should fail the gate: $out"
  fi
done

reset_fixture
write_registry alpha
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha '[check]'
out="$(run_fixture)"
if has_fail_line "$OWNS_TRACKED_CONFIG" &&
  grep -q 'narrow-write shape' <<<"$out" &&
  grep -qE 'alpha[/\\]skills[/\\]setup[/\\]SKILL\.md' <<<"$out"; then
  ok "a carve-out claim from a plugin owning tracked consumer config fails the gate"
else
  fail "a registered tracked-config owner should not reach the carve-out: $out"
fi

reset_fixture
mkdir -p "$TMP/docs/contracts/config-cascade"
{
  echo '# Consumer config cascade (fixture)'
  echo
  echo '## Implementers'
  echo
  echo '| Surface | Consumer config path | Layers | Conformance |'
  echo '|---|---|---|---|'
  echo '| `a-shared-surface` (`alpha`, `gamma`) | `.claude/shared.yaml` | all three | conforms |'
} >"$TMP/docs/contracts/config-cascade/README.md"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha '[check]'
out="$(run_fixture)"
if has_fail_line "$OWNS_TRACKED_CONFIG"; then
  ok "a plugin named alongside the surface it co-owns is read out of the registry row"
else
  fail "a co-owner named in the surface cell should not reach the carve-out: $out"
fi

reset_fixture
write_registry alpha
mkdir -p "$TMP/docs/contracts"
mv "$TMP/docs/conventions/config-cascade" "$TMP/docs/contracts/config-cascade"
mkdir -p "$TMP/docs/conventions/config-cascade"
printf '# Consumer config cascade (moved)\n\nThis contract now lives at docs/contracts/config-cascade/.\n' \
  >"$TMP/docs/conventions/config-cascade/README.md"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha '[check]'
out="$(run_fixture)"
if has_fail_line "$OWNS_TRACKED_CONFIG" && ! grep -q 'must carry an "## Implementers" section' <<<"$out"; then
  ok "the registry is read from docs/contracts/, not the stub left at docs/conventions/"
else
  fail "the moved registry should be read, not the stub: $out"
fi

reset_fixture
make_plugin alpha alpha_api_key
write_setup_skill alpha '[check]' <<'BODY'
## Purpose

`check` reports readiness. There is no `apply` action here.
BODY
out="$(run_fixture)"
if has_fail_line "$NO_DECLARATION"; then
  ok "a skill offering no apply must declare the carve-out, not merely mention apply"
else
  fail "an undeclared carve-out shape should fail the gate: $out"
fi

reset_fixture
write_registry alpha
make_plugin alpha alpha_api_key
write_setup_skill alpha '[check|apply]' <<'BODY'
## Purpose

Check-only under the native `userConfig` surface: `check` reports readiness.
There is no apply action here.
BODY
out="$(run_fixture)"
if has_fail_line "$NO_DOCUMENTED_APPLY"; then
  ok "advertising apply without documenting it fails the gate"
else
  fail "an advertised-but-undocumented apply should fail the gate: $out"
fi

reset_fixture
make_plugin alpha ''
carve_out_body | write_setup_skill alpha '[check]'
out="$(run_fixture)"
if has_fail_line "$NO_USER_CONFIG"; then
  ok "claiming the userConfig-only carve-out with no declared userConfig fails the gate"
else
  fail "an unbacked userConfig-only claim should fail the gate: $out"
fi

reset_fixture
make_plugin alpha ''
write_setup_skill alpha '[check]' <<'BODY'
## Purpose

Check-only under the native `userConfig` surface: `check` reports readiness.
BODY
out="$(run_fixture)"
if has_fail_line "$NO_USER_CONFIG"; then
  ok "doctrine wording that names userConfig without a manifest declaration fails the gate"
else
  fail "a native-userConfig-surface claim with no userConfig should fail: $out"
fi

reset_fixture
make_plugin alpha ''
write_setup_skill alpha '[check]' <<'BODY'
## Purpose

Check-only: this plugin has no `userConfig`. `check` reports external prerequisites.
BODY
out="$(run_fixture)"
if grep -q "$NO_USER_CONFIG" <<<"$out"; then
  fail "denying userConfig should not be read as claiming the surface: $out"
else
  ok "a check-only skill that says it has no userConfig is not an unbacked claim"
fi

reset_fixture
write_registry beta
make_plugin beta ''
write_setup_skill beta '[check|apply] [remove]' <<'BODY'
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
  ok "a narrow-write setup skill owning tracked config passes the carve-out assertions"
fi

reset_fixture
rm -rf "$TMP/docs"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha '[check]'
out="$(run_fixture)"
if has_fail_line "$REGISTRY_MISSING"; then
  ok "a missing consumer-config registry fails the gate"
else
  fail "a missing registry should fail rather than silently skip: $out"
fi

reset_fixture
mkdir -p "$TMP/docs/contracts/config-cascade"
printf '# Consumer config cascade (fixture)\n\nNo Implementers section here.\n' \
  >"$TMP/docs/contracts/config-cascade/README.md"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha '[check]'
out="$(run_fixture)"
if has_fail_line "$REGISTRY_UNSTRUCTURED"; then
  ok "a registry with no Implementers section fails the gate"
else
  fail "a restructured registry should fail rather than silently skip: $out"
fi

reset_fixture
mkdir -p "$TMP/docs/contracts/config-cascade"
{
  echo '# Consumer config cascade (fixture)'
  echo
  echo '## Implementers'
  echo
  echo '| Surface | Consumer config path | Layers | Conformance |'
  echo '|---|---|---|---|'
} >"$TMP/docs/contracts/config-cascade/README.md"
make_plugin alpha alpha_api_key
carve_out_body | write_setup_skill alpha '[check]'
out="$(run_fixture)"
if has_fail_line "$REGISTRY_EMPTY"; then
  ok "an Implementers table naming no surfaces fails the gate"
else
  fail "an empty registry table should fail rather than silently skip: $out"
fi

R_UNKNOWN_KEY='unknown key "'
R_BAD_ENUM='"kind" must be one of file, dir, line'
R_LINE_NO_MATCH='"match" is required when kind is line'
R_HEADING_KIND='"heading" is only allowed when kind is line'
R_HEADING_ATX='"heading" must be an ATX heading'
R_BAD_PATH='"path" must be repo-relative'
R_DUP_ID='duplicate id "'
R_MIGRATE_NO_SUCCESSOR='action migrate requires "successor"'
R_HELPER_MISSING='a plugin shipping retirements.yaml must carry the synced helper'
R_HELPER_DRIFT='must remain byte-identical to plugins/harness-config/lib/check-retirements.sh'
R_CANONICAL_MISSING='it is the canonical helper every plugin shipping retirements.yaml syncs'
R_SETUP_NO_REF='must reference check-retirements.sh when the plugin ships retirements.yaml'
R_REF_NO_MANIFEST='but the plugin ships no retirements.yaml'
R_EVAL_UNCOVERED='no eval covers retirement record "'
R_APPEND_ONLY='records are append-only; demote with `status: report-only` instead'
R_FIELD_CHANGED='changed since HEAD; records are append-only'
R_BASE_UNRESOLVED='does not resolve to a commit'
R_SKIPPED='VALIDATE_CONTRACTS_BASE_REF unset; retirements append-only check skipped'

retirement_failure_lines() {
  grep -E "retirements\.yaml: |check-retirements\.sh|retirement record|ships no retirements" <<<"$out" | grep -E '^- ' || true
}

write_canonical_helper() {
  mkdir -p "$TMP/plugins/harness-config/lib"
  printf '#!/usr/bin/env bash\n# fixture placeholder for the canonical helper\nexit 0\n' \
    >"$TMP/plugins/harness-config/lib/check-retirements.sh"
}

sync_helper() {
  mkdir -p "$TMP/plugins/$1/lib"
  cp "$TMP/plugins/harness-config/lib/check-retirements.sh" "$TMP/plugins/$1/lib/check-retirements.sh"
}

write_manifest() {
  mkdir -p "$TMP/plugins/$1"
  cat >"$TMP/plugins/$1/retirements.yaml"
}

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
heading: '## leftover'
action: remove-line
note: the cache dir moved under the plugin data dir
---
id: alpha-r002
retired: "2026-08-15"
plugin_version: "1.5.0"
kind: file
path: .claude/alpha.json
content_match: '"schema": *"v1"'
action: migrate
successor: "the v1 keys now live in .claude/alpha.md under the Settings heading"
note: "config file replaced by a convention doc"
status: report-only
YAML
}

conforming_retirements_fixture() {
  reset_fixture
  write_canonical_helper
  make_plugin alpha ''
  retiring_setup_body | write_setup_skill alpha '[check|apply]'
  valid_manifest | write_manifest alpha
  sync_helper alpha
  write_evals alpha alpha-r001 alpha-r002
}

conforming_retirements_fixture
out="$(run_fixture)"
if [[ -z "$(retirement_failure_lines)" ]] && grep -q "$R_SKIPPED" <<<"$out"; then
  ok "a conforming retirements manifest raises no retirements failure and reports the skipped append-only check"
else
  fail "a conforming retirements fixture should raise no retirements failure: $out"
fi

malformed_case() {
  local title="$1" needle="$2"
  conforming_retirements_fixture
  write_manifest alpha
  out="$(run_fixture)"
  if has_fail_line "$needle" && grep -qE 'alpha[/\\]retirements\.yaml' <<<"$out"; then
    ok "$title"
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

malformed_case "a block record with an action other than migrate fails the manifest" 'kind block takes only action migrate' <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: block
path: docs/conventions/alpha.yaml
match: '^old_key:'
action: remove-line
note: one line
YAML

malformed_case "a separator with trailing whitespace is not a record break" 'not a "key: value" line' < <({
  cat <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: file
path: .claude/alpha.json
action: delete
note: one line
YAML
  printf '%s \n' '---'
  cat <<'YAML'
id: alpha-r002
retired: 2026-08-02
plugin_version: 1.4.1
kind: file
path: .claude/other.json
action: delete
note: one line
YAML
})

malformed_case "a double-quoted match keeps backslashes instead of unescaping them" 'is not a usable ERE' <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: line
path: .gitignore
match: "\\("
action: remove-line
note: one line
YAML

malformed_case "a path that is the repo root fails the manifest" "$R_BAD_PATH" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: dir
path: .
action: delete
note: one line
YAML

malformed_case "a path with a trailing /. segment fails the manifest" "$R_BAD_PATH" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: dir
path: foo/.
action: delete
note: one line
YAML

malformed_case "a path with a double slash fails the manifest" "$R_BAD_PATH" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: file
path: foo//bar
action: delete
note: one line
YAML

malformed_case "a path with a tab fails the manifest" "$R_BAD_PATH" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: file
path: foo	bar
action: delete
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

malformed_case "heading on a file record fails the manifest" "$R_HEADING_KIND" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: file
path: .claude/alpha.json
heading: "## leftover"
action: delete
note: one line
YAML

malformed_case "a heading that is not ATX fails the manifest" "$R_HEADING_ATX" <<'YAML'
id: alpha-r001
retired: 2026-08-01
plugin_version: 1.4.0
kind: line
path: .gitignore
match: '^x$'
heading: convention_source
action: remove-line
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

conforming_retirements_fixture
rm "$TMP/plugins/alpha/lib/check-retirements.sh"
out="$(run_fixture)"
if has_fail_line "$R_HELPER_MISSING"; then
  ok "a manifest with no synced helper copy fails the gate"
else
  fail "a missing helper copy should fail: $out"
fi

conforming_retirements_fixture
printf '\n' >>"$TMP/plugins/alpha/lib/check-retirements.sh"
out="$(run_fixture)"
if has_fail_line "$R_HELPER_DRIFT"; then
  ok "a helper copy that differs by one byte fails the gate"
else
  fail "a drifted helper copy should fail: $out"
fi

conforming_retirements_fixture
rm "$TMP/plugins/harness-config/lib/check-retirements.sh"
out="$(run_fixture)"
if has_fail_line "$R_CANONICAL_MISSING"; then
  ok "a missing canonical helper fails once by name"
else
  fail "a missing canonical helper should fail: $out"
fi

conforming_retirements_fixture
write_setup_skill alpha '[check|apply]' <<'BODY'
## Purpose

`check` reports drift; `apply` converges this plugin's tracked project config.
BODY
out="$(run_fixture)"
if has_fail_line "$R_SETUP_NO_REF"; then
  ok "a retiring plugin whose setup skill never runs the helper fails the gate"
else
  fail "a setup skill not referencing the helper should fail: $out"
fi

reset_fixture
write_canonical_helper
make_plugin beta ''
retiring_setup_body | write_setup_skill beta '[check|apply]'
out="$(run_fixture)"
if has_fail_line "$R_REF_NO_MANIFEST" && grep -qE 'beta[/\\]skills[/\\]setup[/\\]SKILL\.md' <<<"$out"; then
  ok "a setup skill referencing the helper with no manifest fails the gate"
else
  fail "a dangling helper reference should fail: $out"
fi

reset_fixture
write_canonical_helper
make_plugin beta ''
sync_helper beta
out="$(run_fixture)"
if has_fail_line "$R_REF_NO_MANIFEST" && grep -qE 'beta[/\\]lib[/\\]check-retirements\.sh' <<<"$out"; then
  ok "a helper copy carried with no manifest fails the gate"
else
  fail "a dangling helper copy should fail: $out"
fi

reset_fixture
write_canonical_helper
make_plugin harness-config ''
retiring_setup_body | write_setup_skill harness-config '[check|apply]'
out="$(run_fixture)"
if grep -q "$R_REF_NO_MANIFEST" <<<"$out"; then
  fail "harness-config should be exempt from the inverse wiring check: $out"
else
  ok "harness-config carries the helper and references it without a manifest"
fi

conforming_retirements_fixture
write_evals alpha alpha-r001
out="$(run_fixture)"
if has_fail_line "${R_EVAL_UNCOVERED}alpha-r002" && ! grep -q "${R_EVAL_UNCOVERED}alpha-r001" <<<"$out"; then
  ok "an id no eval names fails by id, and a covered id does not"
else
  fail "an uncovered record id should fail by name: $out"
fi

conforming_retirements_fixture
write_evals alpha alpha-r0010
out="$(run_fixture)"
if has_fail_line "${R_EVAL_UNCOVERED}alpha-r001" && has_fail_line "${R_EVAL_UNCOVERED}alpha-r002"; then
  ok "a longer id that only prefixes a shorter record does not cover it"
else
  fail "a prefixing eval id should not cover the shorter record: $out"
fi

conforming_retirements_fixture
rm -rf "$TMP/plugins/alpha/skills/setup/evals"
out="$(run_fixture)"
if has_fail_line "${R_EVAL_UNCOVERED}alpha-r001\" \\(looked in plugins/alpha/skills/setup/evals/evals.json and plugins/alpha/evals/<case>/\\)" &&
  has_fail_line "${R_EVAL_UNCOVERED}alpha-r002"; then
  ok "with no evals.json and no suite case, every record id fails naming both places looked"
else
  fail "ids covered nowhere should fail by id, naming both places: $out"
fi

write_suite_case() {
  mkdir -p "$TMP/plugins/$1/evals/$2"
  cat >"$TMP/plugins/$1/evals/$2/case.yaml"
  if [[ -n "${3:-}" ]]; then printf '%s\n' "$3" >"$TMP/plugins/$1/evals/$2/prompt.md"; fi
}

conforming_retirements_fixture
rm -rf "$TMP/plugins/alpha/skills/setup/evals"
write_suite_case alpha setup-check-retired-cache \
  "$(printf -- '---\ndescription: "fixture"\n---\n\nRun /alpha:setup check; alpha-r001 is planted.')" <<'YAML'
schema_version: "1.1"
name: setup-check-retired-cache
graders:
  - name: 'names-migrated-file'
    type: 'regex'
    pattern: 'alpha-r002[^\n]*migrat'
    target: 'last_message'
YAML
out="$(run_fixture)"
if [[ -z "$(retirement_failure_lines)" ]]; then
  ok "suite cases cover every record with no evals.json present"
else
  fail "a prompt.md body and a grader pattern should cover the ids: $out"
fi

conforming_retirements_fixture
rm -rf "$TMP/plugins/alpha/skills/setup/evals"
write_suite_case alpha setup-check-retired-cache \
  "$(printf -- '---\ndescription: "alpha-r002 dropped too"\n---\n\nRun /alpha:setup check; alpha-r001 is planted.')" <<'YAML'
schema_version: "1.1"
description: >
  Detects the planted cache. Dropped:
  alpha-r002, which needs a migrate fixture.
name: setup-check-retired-cache
graders:
  - name: 'reports-clean'
    description: 'alpha-r002 dropped'
    type: 'regex'
    pattern: 'clean'
YAML
out="$(run_fixture)"
if has_fail_line "${R_EVAL_UNCOVERED}alpha-r002" && ! grep -q "${R_EVAL_UNCOVERED}alpha-r001" <<<"$out"; then
  ok "an id named only in a suite case's descriptions is not covered"
else
  fail "a description-only id should fail, and the prompt.md id should not: $out"
fi

r002_fixture() {
  conforming_retirements_fixture
  rm -rf "$TMP/plugins/alpha/skills/setup/evals"
  write_suite_case alpha covers-r001 'Run /alpha:setup check; alpha-r001 is planted.' <<<'name: covers-r001'
  write_suite_case alpha probe
}
r002_covered() {
  out="$(run_fixture)"
  if [[ -z "$(retirement_failure_lines)" ]]; then ok "$1"; else fail "$1: $out"; fi
}
r002_uncovered() {
  out="$(run_fixture)"
  if has_fail_line "${R_EVAL_UNCOVERED}alpha-r002" && ! grep -q "${R_EVAL_UNCOVERED}alpha-r001" <<<"$out"; then
    ok "$1"
  else
    fail "$1: $out"
  fi
}

r002_fixture <<'YAML'
graders:
  - description: 'dropped'
    pattern: 'alpha-r002'
YAML
r002_covered "a sibling key after a dash-form description still covers"

r002_fixture <<'YAML'
description: >
  Folded text that names
  nothing to cover.
graders:
  - pattern: 'alpha-r002'
YAML
r002_covered "a key after a top-level block-scalar description still covers"

r002_fixture </dev/null
printf 'description: >\r\n  folded\r\ngraders:\r\n  - pattern: '"'"'alpha-r002'"'"'\r\n' \
  >"$TMP/plugins/alpha/evals/probe/case.yaml"
r002_covered "a CRLF case.yaml still covers through a key after its description"

r002_fixture <<'YAML'
# alpha-r002 is dropped for now
name: probe
YAML
r002_uncovered "an id only in a whole-line comment is not covered"

r002_fixture <<'YAML'
name: probe # alpha-r002 dropped
YAML
r002_uncovered "an id only in a trailing comment is not covered"

r002_fixture <<'YAML'
"description": 'alpha-r002 dropped'
name: probe
YAML
r002_uncovered "an id only in a quoted description key is not covered"

r002_fixture <<'YAML'
graders: [{name: g, description: 'alpha-r002 dropped', type: regex}]
YAML
r002_uncovered "an id only in a flow-mapping description is not covered"

r002_fixture <<'YAML'
graders: [{name: g, description:
  alpha-r002 dropped, type: regex, pattern: clean}]
YAML
r002_uncovered "an id only in a multi-line flow-mapping description is not covered"

r002_fixture <<'YAML'
graders: [
  {name: g, type: regex, pattern: clean, description: x},
  {name: h, type: regex, pattern: clean, description:
  alpha-r002 dropped}]
YAML
r002_uncovered "an id only in a flow description continued at the same column is not covered"

r002_fixture <<'YAML'
graders: [{name: g,
  description:
  alpha-r002}]
YAML
r002_uncovered "an id only in a flow description key on its own line is not covered"

r002_fixture <<'YAML'
graders: [
  {name: g, type: regex, pattern: 'alpha-r002 [ok]'}]
YAML
r002_uncovered "an id in a flow collection does not count, even with no description (fails closed)"

r002_fixture <<'YAML'
graders: &g [{name: h, type: regex, pattern: clean,
  description: x
  alpha-r002}]
YAML
r002_uncovered "an id after an anchored flow collection's description is not covered"

r002_fixture <<'YAML'
graders: [{name: it's, rule: {a: o'k}},
  description: x
  alpha-r002]
YAML
r002_uncovered "an id after apostrophes that hide a flow bracket is not covered"

r002_fixture <<'YAML'
graders:
  - name: g
    type: llm
    criteria: |
      The reply names alpha-r002 and
      the command that removes it.
YAML
r002_covered "an id in a block-scalar criteria value covers"

r002_fixture <<'YAML'
graders:
  - name: alpha-r002
    type: regex
    pattern: clean
YAML
r002_uncovered "an id only in a grader name is not covered"

r002_fixture <<'YAML'
description: |
  Dropped for now; the old grader was
  pattern: alpha-r002
name: probe
YAML
r002_uncovered "a probe-key line inside a description's block scalar is not covered"

r002_fixture <<'YAML'
description: "Dropped:
  prompt: alpha-r002"
name: probe
YAML
r002_uncovered "a probe-key line inside a description's quoted scalar is not covered"

r002_fixture <<'YAML'
description:
  prompt: alpha-r002
name: probe
YAML
r002_uncovered "a probe key under a description mapping is not covered"

r002_fixture <<'YAML'
graders:
  - name: g
    type: regex
    pattern: clean
    "description": |
      pattern: alpha-r002
YAML
r002_uncovered "a probe-key line under a grader's quoted description key is not covered"

r002_fixture <<'YAML'
"description": |
  expected_outcome: alpha-r002
name: probe
YAML
r002_uncovered "a probe-key line under a top-level quoted description key is not covered"

r002_fixture <<'YAML'
? description
: |
  expected_outcome: alpha-r002
name: probe
YAML
r002_uncovered "a probe-key line under an explicit description key is not covered"

r002_fixture <<'YAML'
old notes: |
  expected_outcome: alpha-r002
name: probe
YAML
r002_uncovered "a probe-key line under a spaced key is not covered"

r002_fixture <<'YAML'
execution:
  prompt: |
    Run setup; the leftover is alpha-r002.
YAML
r002_covered "an id in execution.prompt covers"

r002_fixture <<'YAML'
expected_outcome: The run removes alpha-r002 and re-checks.
YAML
r002_covered "an id in a top-level expected_outcome covers"

r002_fixture <<'YAML'
description:
- alpha-r002 dropped
- another note
name: probe
YAML
r002_uncovered "an id only in a description's same-indent sequence is not covered"

r002_fixture <<'YAML'
? description
: alpha-r002 dropped
name: probe
YAML
r002_uncovered "an id only in an explicit-key description is not covered"

r002_fixture <<<'name: probe'
write_suite_case alpha alpha-r002 <<<'name: probe-two'
r002_uncovered "a case directory named the id with an id-free case is not covered"

r002_fixture <<<'name: probe'
mkdir -p "$TMP/plugins/alpha/evals/probe/graders"
printf -- '---\ndescription: "fixture"\n---\n\nPASS when the reply names alpha-r002.\n' \
  >"$TMP/plugins/alpha/evals/probe/graders/names-id.md"
r002_covered "an id in a graders/*.md body covers"

r002_fixture <<<'name: probe'
mkdir -p "$TMP/plugins/alpha/evals/probe/graders"
printf -- '---\ndescription: "alpha-r002 dropped"\n---\n\nPASS when the reply is clean.\n' \
  >"$TMP/plugins/alpha/evals/probe/graders/clean.md"
r002_uncovered "an id only in a graders/*.md frontmatter description is not covered"

r002_fixture <<<'name: probe'
mkdir -p "$TMP/plugins/alpha/evals/results/run1" "$TMP/plugins/alpha/evals/mocks"
printf 'alpha-r002\n' >"$TMP/plugins/alpha/evals/results/run1/prompt.md"
printf 'alpha-r002\n' >"$TMP/plugins/alpha/evals/results/prompt.md"
printf 'name: alpha-r002\n' >"$TMP/plugins/alpha/evals/mocks/case.yaml"
r002_uncovered "an id only under evals/results/ or evals/mocks/ is not covered"

r002_fixture <<<'name: probe'
printf '\xef\xbb\xbf---\ndescription: "alpha-r002 dropped"\n---\n\nRun /alpha:setup check.\n' \
  >"$TMP/plugins/alpha/evals/probe/prompt.md"
r002_uncovered "a BOM-prefixed prompt.md with the id only in frontmatter is not covered"

conforming_retirements_fixture
write_evals alpha alpha-r001
write_suite_case alpha setup-migrate-config 'Run /alpha:setup apply; alpha-r002 is planted.' <<'YAML'
schema_version: "1.1"
name: setup-migrate-config
YAML
out="$(run_fixture)"
if [[ -z "$(retirement_failure_lines)" ]]; then
  ok "an evals.json case and a suite case together cover the manifest"
else
  fail "coverage split across evals.json and a suite case should pass: $out"
fi

conforming_retirements_fixture
printf '{not json\n' >"$TMP/plugins/alpha/skills/setup/evals/evals.json"
out="$(run_fixture)"
if has_fail_line 'is not valid JSON; retirement eval coverage cannot be checked' &&
  has_fail_line "${R_EVAL_UNCOVERED}alpha-r001"; then
  ok "an invalid evals.json fails and covers nothing"
else
  fail "an invalid evals.json should fail and leave its ids uncovered: $out"
fi

run_fixture_with_base() { (cd "$TMP" && VALIDATE_CONTRACTS_BASE_REF="$1" node "$SUT" 2>&1); }
fixture_git() { git_test_config "$TMP" "$@"; }
commit_fixture() {
  rm -rf "$TMP/.git"
  fixture_git init -q
  fixture_git add -A
  fixture_git commit -q -m fixture
}

conforming_retirements_fixture
commit_fixture
valid_manifest | sed '/^id: alpha-r002$/,$d' | write_manifest alpha
out="$(run_fixture_with_base HEAD)"
if has_fail_line "$R_APPEND_ONLY" && grep -q 'record "alpha-r002"' <<<"$out"; then
  ok "deleting a merged record fails the append-only check by id"
else
  fail "a deleted record should fail append-only: $out"
fi

conforming_retirements_fixture
commit_fixture
valid_manifest | sed 's|^path: \.gitignore$|path: .git-ignore|' | write_manifest alpha
out="$(run_fixture_with_base HEAD)"
if has_fail_line "$R_FIELD_CHANGED" && grep -q 'record "alpha-r001": "path" changed' <<<"$out"; then
  ok "rewriting a frozen field on a merged record fails naming the field"
else
  fail "a rewritten frozen field should fail naming it: $out"
fi

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
  ok "a status flip, a note fix, and an appended record pass the append-only check"
fi

conforming_retirements_fixture
commit_fixture
rm "$TMP/plugins/alpha/retirements.yaml"
out="$(run_fixture_with_base HEAD)"
if has_fail_line "$R_APPEND_ONLY" && grep -q 'plugins/alpha/retirements.yaml: was present at HEAD' <<<"$out"; then
  ok "deleting a whole merged manifest fails the append-only check"
else
  fail "a deleted manifest should fail append-only: $out"
fi

conforming_retirements_fixture
commit_fixture
out="$(run_fixture_with_base no-such-ref)"
if grep -qE "^- .*${R_BASE_UNRESOLVED}" <<<"$out"; then
  ok "an unresolvable base ref fails loudly instead of skipping"
else
  fail "an unresolvable base ref should fail: $out"
fi
rm -rf "$TMP/.git"

SKILLS_UNRESOLVED='resolves to no SKILL.md'
SKILLS_DISABLED='cannot be preloaded'
SKILLS_MALFORMED='must be a YAML list of skill names'
CONTRACT_DRIFT='must remain byte-identical to plugins/discovery/skills/report/SKILL.md'
CONTRACT_MISSING_COPY='every preloading plugin must ship the return contract'

write_preloadable_skill() {
  local plugin="$1" skill="$2" disabled="$3"
  mkdir -p "$TMP/plugins/$plugin/skills/$skill"
  {
    echo '---'
    printf 'description: "Fixture skill %s."\n' "$skill"
    echo 'user-invocable: false'
    printf 'disable-model-invocation: %s\n' "$disabled"
    echo '---'
    echo
    echo 'Fixture body.'
  } >"$TMP/plugins/$plugin/skills/$skill/SKILL.md"
}

write_agent() {
  local plugin="$1" agent="$2"
  mkdir -p "$TMP/plugins/$plugin/agents"
  {
    echo '---'
    printf 'name: %s\n' "$agent"
    printf 'description: "Fixture agent %s."\n' "$agent"
    cat
    echo '---'
    echo
    echo 'Fixture agent body.'
  } >"$TMP/plugins/$plugin/agents/$agent.md"
}

write_contract_copy() {
  local plugin="$1" body="$2"
  mkdir -p "$TMP/plugins/$plugin/skills/report/evals"
  {
    echo '---'
    echo 'description: "Fixture return contract."'
    echo 'user-invocable: false'
    echo 'disable-model-invocation: false'
    echo '---'
    echo
    echo "$body"
  } >"$TMP/plugins/$plugin/skills/report/SKILL.md"
  printf '{"skill_name": "report", "evals": []}\n' \
    >"$TMP/plugins/$plugin/skills/report/evals/evals.json"
}

reset_fixture
make_plugin alpha ''
write_preloadable_skill alpha explore false
write_agent alpha explorer <<'YAML'
skills:
  - alpha:explor
YAML
out="$(run_fixture)"
if has_fail_line "$SKILLS_UNRESOLVED" &&
  grep -q 'alpha:explor' <<<"$out" &&
  grep -qE 'alpha[/\\]agents[/\\]explorer\.md' <<<"$out"; then
  ok "a \`skills:\` entry naming no SKILL.md fails the gate, naming the agent and the entry"
else
  fail "an unresolvable skills: entry should fail the gate: $out"
fi

reset_fixture
make_plugin alpha ''
write_preloadable_skill alpha explore true
write_agent alpha explorer <<'YAML'
skills:
  - alpha:explore
YAML
out="$(run_fixture)"
if has_fail_line "$SKILLS_DISABLED" && grep -q 'alpha:explore' <<<"$out"; then
  ok "a \`skills:\` entry targeting a disable-model-invocation skill fails the gate"
else
  fail "a disable-model-invocation preload target should fail the gate: $out"
fi

for spelling in yes ON 1 'true # class (i)'; do
  reset_fixture
  make_plugin alpha ''
  write_preloadable_skill alpha explore "$spelling"
  write_agent alpha explorer <<'YAML'
skills:
  - alpha:explore
YAML
  out="$(run_fixture)"
  if has_fail_line "$SKILLS_DISABLED"; then
    ok "a preload target spelled '$spelling' fails the gate"
  else
    fail "a preload target spelled '$spelling' should fail the gate: $out"
  fi
done
for spelling in no OFF 0; do
  reset_fixture
  make_plugin alpha ''
  write_preloadable_skill alpha explore "$spelling"
  write_agent alpha explorer <<'YAML'
skills:
  - alpha:explore
YAML
  out="$(run_fixture)"
  if grep -q "$SKILLS_DISABLED" <<<"$out"; then
    fail "a preload target spelled '$spelling' should pass the guard: $out"
  else
    ok "a preload target spelled '$spelling' passes the guard"
  fi
done

reset_fixture
make_plugin alpha ''
make_plugin beta ''
write_preloadable_skill beta thing false
write_agent alpha explorer <<'YAML'
skills:
  - beta:thing
YAML
out="$(run_fixture)"
if grep -q "$SKILLS_UNRESOLVED" <<<"$out" || grep -q "$SKILLS_DISABLED" <<<"$out"; then
  fail "the namespaced plugin:skill form should resolve: $out"
else
  ok "the namespaced \`plugin:skill\` form resolves to the named plugin's skill"
fi

reset_fixture
make_plugin alpha ''
make_plugin beta ''
write_preloadable_skill alpha thing false
write_preloadable_skill beta thing true
write_agent alpha explorer <<'YAML'
skills:
  - thing
YAML
out="$(run_fixture)"
if grep -q "$SKILLS_UNRESOLVED" <<<"$out" || grep -q "$SKILLS_DISABLED" <<<"$out"; then
  fail "a bare skills: entry should resolve against the agent's own plugin: $out"
else
  ok "a bare \`skills:\` entry resolves against the agent's own plugin"
fi

reset_fixture
make_plugin alpha ''
write_preloadable_skill alpha explore false
write_agent alpha explorer <<'YAML'
skills: alpha:explore
YAML
out="$(run_fixture)"
if has_fail_line "$SKILLS_MALFORMED"; then
  ok "a \`skills:\` key in an unparsed shape fails rather than checking nothing"
else
  fail "a malformed skills: key should fail the gate: $out"
fi

reset_fixture
write_contract_copy discovery 'The canonical contract text.'
write_contract_copy implementation 'The canonical contract text.'
write_contract_copy plugin-quality 'The canonical contract text.'
out="$(run_fixture)"
if grep -q "$CONTRACT_DRIFT" <<<"$out" || grep -q "$CONTRACT_MISSING_COPY" <<<"$out"; then
  fail "three identical return-contract copies should raise no drift failure: $out"
else
  ok "three byte-identical return-contract copies pass the copy assertions"
fi

reset_fixture
write_contract_copy discovery 'The canonical contract text.'
write_contract_copy implementation 'The canonical contract text.'
write_contract_copy plugin-quality 'The canonical contract text, edited.'
out="$(run_fixture)"
if has_fail_line "$CONTRACT_DRIFT" &&
  grep -qE 'plugin-quality[/\\]skills[/\\]report[/\\]SKILL\.md' <<<"$out"; then
  ok "a drifted return-contract copy fails the gate, naming the canonical copy"
else
  fail "a drifted return-contract copy should fail the gate: $out"
fi

reset_fixture
write_contract_copy discovery 'The canonical contract text.'
write_contract_copy implementation 'The canonical contract text.'
out="$(run_fixture)"
if has_fail_line "$CONTRACT_MISSING_COPY" &&
  grep -qE 'plugin-quality[/\\]skills[/\\]report[/\\]SKILL\.md' <<<"$out"; then
  ok "a preloading plugin shipping no return-contract copy fails the gate"
else
  fail "a missing return-contract copy should fail the gate: $out"
fi

A_NO_MODEL='agent definitions must name a model'
A_BARE_INHERIT='model: inherit needs a trailing'
A_DUPLICATE='model: appears more than once'
A_MALFORMED='model: line is malformed'

make_agent() {
  local plugin="$1" name="$2" model_line="$3"
  mkdir -p "$TMP/plugins/$plugin/agents"
  {
    echo '---'
    printf 'name: %s\n' "$name"
    printf 'description: "Fixture agent %s."\n' "$name"
    echo 'tools: "Read"'
    if [[ -n "$model_line" ]]; then printf '%s\n' "$model_line"; fi
    echo 'effort: high'
    echo '---'
    echo
    echo 'Fixture body.'
  } >"$TMP/plugins/$plugin/agents/$name.md"
}

agent_fail_line() {
  grep -qE "^- .*agents[/\\\\]$1\.md: .*$2" <<<"$out"
}

agent_any_fail() {
  agent_fail_line "$1" "$A_NO_MODEL" || agent_fail_line "$1" "$A_BARE_INHERIT" ||
    agent_fail_line "$1" "$A_DUPLICATE" || agent_fail_line "$1" "$A_MALFORMED"
}

reset_fixture
make_plugin alpha ''
make_agent alpha no-model ''
make_agent alpha bare-inherit 'model: inherit'
make_agent alpha reasoned-inherit "model: inherit  # reason: must match the orchestrator's model"
make_agent alpha named-alias 'model: sonnet'
printf '%s\r\n' '---' 'name: crlf-opus' 'description: "Fixture agent crlf-opus."' \
  'model: opus' '---' '' 'Fixture body.' >"$TMP/plugins/alpha/agents/crlf-opus.md"
if [[ "$(tr -dc '\r' <"$TMP/plugins/alpha/agents/crlf-opus.md" | wc -c)" -eq 7 ]]; then
  ok "the CRLF fixture carries a carriage return on every line"
else
  fail "the CRLF fixture should carry 7 carriage returns"
fi
{
  echo '---'
  echo 'name: body-model'
  echo 'description: "Fixture agent whose model line sits in the body."'
  echo '---'
  echo
  echo 'model: opus'
} >"$TMP/plugins/alpha/agents/body-model.md"
make_agent alpha quoted-inherit 'model: "inherit"  # reason: x'
make_agent alpha empty-reason 'model: inherit  # reason:'
make_agent alpha capital-inherit 'model: Inherit'
make_agent alpha prefixed-key 'modelFoo: x'
make_agent alpha nested-model $'metadata:\n  model: opus'
make_agent alpha hash-in-quotes 'model: "a#b"'
make_agent alpha spaced-comment 'model: opus  # the reviewer tier'
mkdir -p "$TMP/plugins/alpha/agents/review"
make_agent alpha review/nested-no-model ''
make_agent alpha block-literal $'model: |-\n  inherit'
make_agent alpha block-folded $'model: >\n  inherit'
make_agent alpha null-word 'model: null'
make_agent alpha null-tilde 'model: ~'
make_agent alpha null-capital 'model: Null'
make_agent alpha duplicate-model $'model: opus\nmodel: inherit'
make_agent alpha no-space-colon 'model:opus'
make_agent alpha glued-hash 'model: inherit#reason: x'
{
  printf '\xEF\xBB\xBF'
  echo '---'
  echo 'name: bom-opus'
  echo 'description: "Fixture agent bom-opus."'
  echo 'model: opus'
  echo '---'
  echo
  echo 'Fixture body.'
} >"$TMP/plugins/alpha/agents/bom-opus.md"
out="$(run_fixture)"

if agent_fail_line no-model "$A_NO_MODEL"; then
  ok "an agent definition with no model line fails the gate"
else
  fail "an agent with no model line should fail: $out"
fi

if agent_fail_line bare-inherit "$A_BARE_INHERIT"; then
  ok "model: inherit with no stated reason fails the gate"
else
  fail "a bare model: inherit should fail: $out"
fi

if agent_any_fail reasoned-inherit; then
  fail "model: inherit with a trailing reason comment should pass: $out"
else
  ok "model: inherit with a trailing # reason: comment passes"
fi

if agent_any_fail named-alias; then
  fail "an explicit model alias should pass: $out"
else
  ok "an agent naming an explicit model alias passes"
fi

if agent_any_fail crlf-opus; then
  fail "a CRLF-terminated agent naming a model should pass: $out"
else
  ok "a CRLF-terminated agent definition naming a model passes"
fi

if agent_fail_line body-model "$A_NO_MODEL"; then
  ok "a model line outside the frontmatter does not count"
else
  fail "a model line in the body only should fail as missing: $out"
fi

if agent_any_fail quoted-inherit; then
  fail "a quoted inherit with a reason comment should pass: $out"
else
  ok "model: \"inherit\" with a trailing # reason: comment passes"
fi

if agent_fail_line empty-reason "$A_BARE_INHERIT"; then
  ok "model: inherit with an empty # reason: fails as bare inherit"
else
  fail "an empty reason comment should fail as bare inherit: $out"
fi

if agent_fail_line capital-inherit "$A_BARE_INHERIT"; then
  ok "model: Inherit is compared case-insensitively and fails as bare inherit"
else
  fail "model: Inherit should fail as bare inherit: $out"
fi

if agent_fail_line prefixed-key "$A_NO_MODEL"; then
  ok "a modelFoo: key does not count as a model line"
else
  fail "a modelFoo: key alone should fail as missing: $out"
fi

if agent_fail_line nested-model "$A_NO_MODEL"; then
  ok "an indented model: under a nested key does not count"
else
  fail "an indented nested model: should fail as missing: $out"
fi

if agent_any_fail bom-opus; then
  fail "a BOM-prefixed agent naming a model should pass: $out"
else
  ok "a BOM-prefixed agent definition naming a model passes"
fi

if agent_any_fail hash-in-quotes; then
  fail "a quoted model value containing # should pass: $out"
else
  ok "a quoted model value containing # is kept whole and passes"
fi

if agent_any_fail spaced-comment; then
  fail "a model value followed by whitespace and a # comment should pass: $out"
else
  ok "a model value followed by whitespace and a # comment passes"
fi

if agent_fail_line 'review[/\\]nested-no-model' "$A_NO_MODEL"; then
  ok "an agent nested under agents/<dir>/ with no model line fails the gate"
else
  fail "a nested agent with no model line should fail: $out"
fi

for name in block-literal block-folded; do
  if agent_fail_line "$name" "$A_MALFORMED"; then
    ok "a block-scalar model value ($name) fails as malformed"
  else
    fail "a block-scalar model value ($name) should fail as malformed: $out"
  fi
done

for name in null-word null-tilde null-capital; do
  if agent_fail_line "$name" "$A_NO_MODEL"; then
    ok "a YAML null model value ($name) fails as missing"
  else
    fail "a YAML null model value ($name) should fail as missing: $out"
  fi
done

if agent_fail_line duplicate-model "$A_DUPLICATE"; then
  ok "two model: keys in one frontmatter fail as a duplicate"
else
  fail "duplicate model: keys should fail: $out"
fi

if agent_fail_line no-space-colon "$A_MALFORMED"; then
  ok "model:opus with no whitespace after the colon fails as malformed"
else
  fail "model:opus should fail as malformed: $out"
fi

if agent_fail_line glued-hash "$A_MALFORMED"; then
  ok "model: inherit#reason: x with no whitespace before # fails as malformed"
else
  fail "a # glued to the value should fail as malformed: $out"
fi

write_arg_body() {
  local plugin="$1" skill="$2" hint="$3"
  mkdir -p "$TMP/plugins/$plugin/skills/$skill"
  {
    echo '---'
    echo 'description: "Fixture skill."'
    if [[ "$hint" != "-" ]]; then
      printf 'argument-hint: "%s"\n' "$hint"
    fi
    if [[ "$hint" == "NAMED" ]]; then
      echo 'arguments: [tier]'
    fi
    echo 'disable-model-invocation: false'
    echo '---'
    echo
    cat
  } >"$TMP/plugins/$plugin/skills/$skill/SKILL.md"
}

ARG_DOC='skill-authoring/SKILL.md'

reset_fixture
make_plugin argname ""
printf 'Use $1 here.\n' | write_arg_body argname digit '[tier]'
out="$(run_fixture)"
if has_fail_line 'unescaped \$1' && grep -q "$ARG_DOC" <<<"$out" &&
  grep -q 'argname/skills/digit/SKILL.md' <<<"$out"; then
  ok "an unescaped \$1 in a skill with an argument-hint fails"
else
  fail "an unescaped \$1 should fail: $out"
fi

reset_fixture
make_plugin argname ""
printf 'Use \$1 here.\n' | write_arg_body argname escaped '[tier]'
out="$(run_fixture)"
if grep -q 'argname/skills/escaped/SKILL.md' <<<"$out"; then
  fail "a single-backslash escape should pass: $out"
else
  ok 'a single-backslash \$1 passes'
fi

reset_fixture
make_plugin argname ""
printf 'Use $1 in a shell example.\n' | write_arg_body argname noarg -
out="$(run_fixture)"
if grep -q 'argname/skills/noarg/SKILL.md' <<<"$out"; then
  fail "a no-argument skill should keep a literal \$1: $out"
else
  ok "a no-argument skill may contain \$1"
fi

reset_fixture
make_plugin argname ""
printf 'Price is \\\\$1 today.\n' | write_arg_body argname doubled NAMED
out="$(run_fixture)"
if has_fail_line 'unescaped \$1' && grep -q 'argname/skills/doubled/SKILL.md' <<<"$out"; then
  ok "a doubled backslash does not escape \$1"
else
  fail "a doubled backslash before \$1 should fail: $out"
fi

reset_fixture
make_plugin argname ""
printf 'Parse $ARGUMENTS only.\n' | write_arg_body argname plain '[tier]'
out="$(run_fixture)"
if grep -q 'argname/skills/plain/SKILL.md' <<<"$out"; then
  fail "\$ARGUMENTS without \$N should pass: $out"
else
  ok "\$ARGUMENTS without an indexed placeholder passes"
fi

HINT_DOC='docs/contracts/argument-hint/README.md'
HINT_MALFORMED='argument-hint is malformed'

hint_case() {
  reset_fixture
  make_plugin hintfix ""
  printf 'Body.\n' | write_arg_body hintfix "$1" "$2"
  out="$(run_fixture)"
}

for good in "[on|off]" \
  "[low|medium|high|xhigh|max|ultra] [--fix] [--comment] [pr#|branch|path]" \
  "[reconnect <server>|enable|disable [<server>|all]]" \
  "[check|apply] [args]" "<check|apply> [--mode <name>]" "[<dir>]... [path ...]" \
  "check" "--plan-file <path> [--apply]" "[scan|caches|aliases…] [args]"; do
  hint_case ok "$good"
  if grep -q 'hintfix/skills/ok/SKILL.md' <<<"$out"; then
    fail "a conforming argument-hint should be silent ($good): $out"
  else
    ok "a conforming argument-hint draws neither a failure nor a warning: $good"
  fi
done

hint_case empty ""
if has_fail_line 'argument-hint must be omitted' && grep -q "$HINT_DOC" <<<"$out" &&
  grep -q 'hintfix/skills/empty/SKILL.md' <<<"$out"; then
  ok "an empty-string argument-hint fails and names the owner doc"
else
  fail "an empty-string argument-hint should fail: $out"
fi

for commented in '"" # none' '# none'; do
  hint_case commented x
  skill_md="$TMP/plugins/hintfix/skills/commented/SKILL.md"
  sed "s/^argument-hint: \"x\"\$/argument-hint: $commented/" "$skill_md" >"$skill_md.new" && mv "$skill_md.new" "$skill_md"
  out="$(run_fixture)"
  if has_fail_line 'argument-hint must be omitted' && grep -q 'hintfix/skills/commented/SKILL.md' <<<"$out"; then
    ok "an argument-hint that is only a YAML comment fails as empty: $commented"
  else
    fail "an argument-hint that is only a YAML comment should fail as empty ($commented): $out"
  fi
done

hint_case long "$(printf 'x%.0s' {1..101})"
if grep -q "^warning: .*hintfix/skills/long/SKILL.md.*101 characters, over the 100-character budget.*$HINT_DOC" <<<"$out" &&
  ! has_fail_line 'budget'; then
  ok "an over-budget argument-hint warns and does not fail"
else
  fail "an over-budget argument-hint should warn without failing: $out"
fi

hint_case edge "$(printf 'x%.0s' {1..100})"
if grep -q 'hintfix/skills/edge/SKILL.md' <<<"$out"; then
  fail "a 100-character argument-hint is inside the budget: $out"
else
  ok "a 100-character argument-hint is inside the budget"
fi

while IFS=$'\t' read -r shape reason; do
  hint_case bad "$shape"
  if grep -qF "hintfix/skills/bad/SKILL.md: $HINT_MALFORMED: $reason ($HINT_DOC)" <<<"$out" &&
    grep -q "^warning: .*hintfix/skills/bad/SKILL.md" <<<"$out" &&
    ! has_fail_line "$HINT_MALFORMED"; then
    ok "a malformed argument-hint warns ($reason): $shape"
  else
    fail "a malformed argument-hint should warn '$reason' without failing ($shape): $out"
  fi
done <<'SHAPES'
[check] — [apply]	em dash
[check]. Default: apply	Default: prose
[plan | apply]	spaced pipe
check | apply	spaced pipe
check | apply	alternatives outside [] or <>
check|apply	alternatives outside [] or <>
[audit]|[sweep]	alternatives outside [] or <>
[action] [args]	placeholder slot instead of the written-out set
<action>	placeholder slot instead of the written-out set
[mode]	placeholder slot instead of the written-out set
[--<mode>] [domain|board]	placeholder slot instead of the written-out set
[task or mode]	placeholder slot instead of the written-out set
[--execute] [options] <dir>	placeholder slot instead of the written-out set
[check] (e.g., apply)	prose outside the grammar
[topic] (empty = the previous response)	prose outside the grammar
[section]: allow to focus the interview	prose outside the grammar
[terminal|file]. Omit to auto-decide	prose outside the grammar
<x-url>, a status URL	prose outside the grammar
[incumbent [target]] or [plan]	prose outside the grammar
<path> defaults to cwd	prose outside the grammar
[path] omit for current repo	prose outside the grammar
<url> x URL	prose outside the grammar
[x] runs	prose outside the grammar
[scan…|all]	… not closing a shortened set
<path>…	… not closing a shortened set
SHAPES

hint_case flag "[--mode <name>] [--options <file>]"
if grep -q "hintfix/skills/flag/SKILL.md.*placeholder" <<<"$out"; then
  fail "a literal --mode flag is not a placeholder slot: $out"
else
  ok "a literal --mode or --options flag is not a placeholder slot"
fi

LEADING_CHECK='must declare check as the leading action'
for good in '[check]' '[check|apply]' '<check|apply> [remove]' '[check] [verify-api]'; do
  reset_fixture
  make_plugin alpha alpha_api_key
  carve_out_body | write_setup_skill alpha "$good"
  out="$(run_fixture)"
  if grep -q "$LEADING_CHECK" <<<"$out"; then
    fail "a setup hint leading with $good should pass the leading-check contract: $out"
  else
    ok "a setup hint leading with $good passes the leading-check contract"
  fi
done
for bad in 'check' 'check | apply' 'check [verify-api]' '[apply|check]' '[checker]'; do
  reset_fixture
  make_plugin alpha alpha_api_key
  carve_out_body | write_setup_skill alpha "$bad"
  out="$(run_fixture)"
  if has_fail_line "$LEADING_CHECK.*$HINT_DOC"; then
    ok "a setup hint of $bad fails the leading-check contract and names the owner doc"
  else
    fail "a setup hint of $bad should fail the leading-check contract: $out"
  fi
done

agree_case() {
  reset_fixture
  make_plugin hintfix ""
  write_arg_body hintfix "$1" "[tier] <path>"
  out="$(run_fixture)"
}

AGREE='does not lead with the argument-hint'

agree_case match < <(printf '**Arguments.** `[tier] <path>`. Full form: `[tier] [--x] <path>`.\n')
if grep -q 'hintfix/skills/match/SKILL.md' <<<"$out"; then
  fail "an Arguments line leading with the hint should be silent: $out"
else
  ok "an Arguments line leading with the hint is silent"
fi

agree_case differ < <(printf '**Arguments.** `[tier]`.\n')
if grep -q "^warning: .*hintfix/skills/differ/SKILL.md.*$AGREE.*$HINT_DOC" <<<"$out" &&
  ! has_fail_line "$AGREE"; then
  ok "an Arguments line that differs from the hint warns, names the owner doc, and does not fail"
else
  fail "a differing Arguments line should warn without failing: $out"
fi

agree_case noline < <(printf 'Body.\n')
if grep -q 'hintfix/skills/noline/SKILL.md' <<<"$out"; then
  fail "a hint with no Arguments line should be silent: $out"
else
  ok "a hint with no Arguments line is silent"
fi

agree_case fenced < <(printf '```\n**Arguments.** `[other]`\n```\n')
if grep -q 'hintfix/skills/fenced/SKILL.md' <<<"$out"; then
  fail "an Arguments line inside a fence should be ignored: $out"
else
  ok "an Arguments line inside a fenced block is ignored"
fi

agree_case nospan < <(printf '**Arguments.** none listed here.\n')
if grep -q "^warning: .*hintfix/skills/nospan/SKILL.md.*$AGREE" <<<"$out"; then
  ok "an Arguments line without an inline span warns"
else
  fail "an Arguments line without a span should warn: $out"
fi

agree_case longfence < <(printf '````\n```\n**Arguments.** `[other]`\n````\n')
if grep -q 'hintfix/skills/longfence/SKILL.md' <<<"$out"; then
  fail "a shorter fence line should not close a longer fence: $out"
else
  ok "an Arguments line inside a four-backtick fence holding a three-backtick line is ignored"
fi

agree_case tildefence < <(printf '~~~\n```\n~~~\n**Arguments.** `[other]`\n')
if grep -q "^warning: .*hintfix/skills/tildefence/SKILL.md.*$AGREE" <<<"$out"; then
  ok "a fence closes only on its own marker, so the line after it is checked"
else
  fail "the line after a closed tilde fence should be checked: $out"
fi

reset_fixture
make_plugin hintfix ""
mkdir -p "$TMP/plugins/hintfix/skills/fmfence"
printf -- '---\nargument-hint: "[tier]"\ndescription: "Fixture. Ends with ```"\n---\n\n**Arguments.** `[other]`\n' \
  >"$TMP/plugins/hintfix/skills/fmfence/SKILL.md"
out="$(run_fixture)"
if grep -q "^warning: .*hintfix/skills/fmfence/SKILL.md.*$AGREE" <<<"$out"; then
  ok "a fence marker ending the frontmatter does not hide the Arguments line"
else
  fail "frontmatter ending in a fence marker should not hide the Arguments line: $out"
fi

OPT_DOC='docs/contracts/plugin-option-naming/README.md'

write_plugin_manifest() {
  mkdir -p "$TMP/plugins/$1/.claude-plugin"
  printf '{"version": "0.1.0",\n"name": "%s",\n"description": "fixture"%s}\n' "$1" "$2" \
    >"$TMP/plugins/$1/.claude-plugin/plugin.json"
}

option_case() {
  reset_fixture
  write_plugin_manifest optfix ", \"userConfig\": {\"opt\": {\"type\": \"$1\", \"title\": \"$2\", \"description\": \"$3\"}}"
  out="$(run_fixture)"
}

reset_fixture
write_plugin_manifest optfix ', "displayName": "Opt Fix"'
out="$(run_fixture)"
if grep -qF -- "- plugins/optfix/.claude-plugin/plugin.json: plugins must not set displayName ($OPT_DOC)" <<<"$out"; then
  ok "a displayName in plugin.json fails"
else
  fail "a displayName in plugin.json should fail: $out"
fi

reset_fixture
mkdir -p "$TMP/.claude-plugin"
printf '{"plugins": [{"name": "optfix", "source": "./plugins/optfix", "displayName": "Opt Fix"}, {"name": "clean", "source": "./plugins/clean"}]}\n' \
  >"$TMP/.claude-plugin/marketplace.json"
out="$(run_fixture)"
rm -rf "$TMP/.claude-plugin"
if has_fail_line 'plugin entry "optfix" must not set displayName' && ! grep -q 'plugin entry "clean"' <<<"$out"; then
  ok "a displayName in a marketplace entry fails, and only that entry"
else
  fail "a displayName in a marketplace entry should fail for that entry only: $out"
fi

while IFS=$'\t' read -r type title description; do
  option_case "$type" "$title" "$description"
  if grep -q 'optfix' <<<"$out"; then
    fail "a conforming option should be silent ($title): $out"
  else
    ok "a conforming option draws neither a failure nor a warning: $title"
  fi
done <<'GOOD'
boolean	Bash-format hook	Runs the hook after each edit.
string	API token	The token the plugin sends.
number	30-day window (days)	How far back to look.
string	CI ID	Plain text with a [bracket] and a (paren).
boolean	Optimization report	Master is fine in a description; enabled too.
string	Optfixer mode	Starts with the plugin name only as a prefix of a longer word.
string	API URL	Two acronyms side by side.
boolean	Block-Windows-drive-tmp guard	A proper noun after the first word.
string	Allow-list	Permits ps-unparsable-* tokens and a bare * alone.
GOOD

while IFS=$'\t' read -r type title description problem; do
  option_case "$type" "$title" "$description"
  if grep -qF "warning: plugins/optfix/.claude-plugin/plugin.json: userConfig \"opt\" $problem ($OPT_DOC)" <<<"$out" &&
    ! has_fail_line 'userConfig "opt"'; then
    ok "an option warns without failing: $problem"
  else
    fail "an option should warn '$problem' without failing: $out"
  fi
done <<'SHAPES'
string	output directory	Where files go.	title "output directory": not sentence case
string	-Output directory	Where files go.	title "-Output directory": not sentence case
string	OUTPUT DIRECTORY	Where files go.	title "OUTPUT DIRECTORY": not sentence case
string	Output DIRECTORY	Where files go.	title "Output DIRECTORY": not sentence case
string	Output Directory	Where files go.	title "Output Directory": not sentence case
string	Optfix output directory	Where files go.	title "Optfix output directory": opens with the plugin name
boolean	Enable the hook	Runs it.	title "Enable the hook": boolean title uses enable, enabled, toggle, kill switch, or master
boolean	Hook enabled	Runs it.	title "Hook enabled": boolean title uses enable, enabled, toggle, kill switch, or master
boolean	Hook toggle	Runs it.	title "Hook toggle": boolean title uses enable, enabled, toggle, kill switch, or master
boolean	Hook kill switch	Runs it.	title "Hook kill switch": boolean title uses enable, enabled, toggle, kill switch, or master
boolean	Master hook	Runs it.	title "Master hook": boolean title uses enable, enabled, toggle, kill switch, or master
string	Output directory	Uses `dir`.	description contains a backtick
string	Output directory	Uses **dir**.	description contains **
string	Output directory	Uses *strict* mode.	description contains *emphasis*
string	Output directory	See [the docs](https://x.test).	description contains a markdown link
string	Output directory	Where files go — always.	description contains an em dash
SHAPES

reset_fixture
mkdir -p "$TMP/plugins/opt-fix/.claude-plugin"
printf '{"name": "opt-fix", "userConfig": {"opt": {"type": "string", "title": "Opt fix mode"}}}\n' \
  >"$TMP/plugins/opt-fix/.claude-plugin/plugin.json"
out="$(run_fixture)"
if grep -qF 'title "Opt fix mode": opens with the plugin name' <<<"$out"; then
  ok "a title opening with the hyphenated plugin name spelled with a space warns"
else
  fail "a title opening with the plugin name spelled with a space should warn: $out"
fi

option_case string "Toggle key" "A key."
if grep -q 'boolean title uses' <<<"$out"; then
  fail "a non-boolean title should not draw the boolean-word warning: $out"
else
  ok "a non-boolean title is exempt from the boolean-word rule"
fi

option_case string "Output directory" "$(printf 'x%.0s' {1..301})"
if grep -qF 'userConfig "opt" description is 301 characters, over the 300-character budget' <<<"$out" &&
  ! has_fail_line 'description is'; then
  ok "a 301-character description warns without failing"
else
  fail "a 301-character description should warn without failing: $out"
fi
option_case string "Output directory" "$(printf 'x%.0s' {1..300})"
if grep -q 'over the 300-character budget' <<<"$out"; then
  fail "a 300-character description is inside the budget: $out"
else
  ok "a 300-character description is inside the budget"
fi

reset_fixture
write_plugin_manifest alpha ', "userConfig": {"output_dir": {"type": "directory", "title": "Output directory"}}'
write_plugin_manifest beta ', "userConfig": {"output_dir": {"type": "directory", "title": "Output folder"}}'
write_plugin_manifest gamma ', "userConfig": {"output_dir": {"type": "directory", "title": "Output directory"}}'
out="$(run_fixture)"
if grep -qF "warning: userConfig \"output_dir\" has different titles across plugins: \"Output directory\" (alpha, gamma); \"Output folder\" (beta) ($OPT_DOC)" <<<"$out" &&
  [[ "$(grep -c 'has different titles' <<<"$out")" -eq 1 ]]; then
  ok "a key carrying different titles across plugins warns once, naming each title and plugin"
else
  fail "a key with different titles across plugins should warn once: $out"
fi
reset_fixture
write_plugin_manifest alpha ', "userConfig": {"output_dir": {"type": "directory", "title": "Output directory"}}'
write_plugin_manifest beta ', "userConfig": {"output_dir": {"type": "directory", "title": "Output directory"}}'
out="$(run_fixture)"
if grep -q 'has different titles' <<<"$out"; then
  fail "a key with one title across plugins should be silent: $out"
else
  ok "a key carrying the same title across plugins is silent"
fi

reset_fixture
write_plugin_manifest syncfix ', "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json", "defaultEnabled": false'
long="$(printf 'a%.0s' {1..501})"
write_plugin_manifest longfix ''
printf '{"version": "0.1.0",\n"name": "longfix",\n"description": "%s"}\n' "$long" >"$TMP/plugins/longfix/.claude-plugin/plugin.json"
write_plugin_manifest okfix ''
out="$(run_fixture)"
if has_fail_line 'must not set \$schema' && has_fail_line 'must not set defaultEnabled' &&
  grep -qE '^- .*longfix.*description is 501 characters' <<<"$out" &&
  ! grep -qE 'okfix..claude-plugin' <<<"$out"; then
  ok "\$schema, defaultEnabled, a description over 500 fail, and a conforming manifest passes"
else
  fail "claude.ai manifest limits should fail as stated: $out"
fi

reset_fixture
mkdir -p "$TMP/plugins/adjfix/.claude-plugin" "$TMP/plugins/samefix/.claude-plugin" "$TMP/plugins/nestfix/.claude-plugin" \
  "$TMP/plugins/gapfix/evals/case/.claude-plugin"
printf '{\n  "name": "evalfix",\n  "version": "0.1.0",\n  "description": "fixture"\n}\n' \
  >"$TMP/plugins/gapfix/evals/case/.claude-plugin/plugin.json"
printf '{\n  "name": "adjfix",\n  "version": "0.1.0",\n  "description": "fixture"\n}\n' \
  >"$TMP/plugins/adjfix/.claude-plugin/plugin.json"
printf '{"name": "samefix", "version": "0.1.0", "description": "fixture"}\n' \
  >"$TMP/plugins/samefix/.claude-plugin/plugin.json"
printf '{\n  "name": "nestfix",\n  "userConfig": {"opt": {"type": "string",\n    "description": "nested"}},\n  "version": "0.1.0",\n  "license": "MIT",\n  "description": "fixture"\n}\n' \
  >"$TMP/plugins/nestfix/.claude-plugin/plugin.json"
write_plugin_manifest gapfix ''
out="$(run_fixture)"
if grep -qF -- '- plugins/adjfix/.claude-plugin/plugin.json: "version" (line 3) and "description" (line 4) touch' <<<"$out" &&
  grep -qF -- '- plugins/samefix/.claude-plugin/plugin.json: "version" (line 1) and "description" (line 1) touch' <<<"$out" &&
  ! grep -qE '(nestfix|gapfix).*touch' <<<"$out"; then
  ok "a manifest whose version and description lines touch fails; one with a line between them, or a nested one, passes"
else
  fail "touching version and description lines should fail, and only those: $out"
fi

write_skill() {
  mkdir -p "$(dirname "$TMP/plugins/skfix/skills/$1")"
  printf '%s' "$2" >"$TMP/plugins/skfix/skills/$1"
}
reset_fixture
write_plugin_manifest skfix ''
write_skill good/SKILL.md $'---\nname: good\ndescription: >-\n  Folded text, a\n  second line.\n---\nbody\n'
write_skill angle/SKILL.md $'---\ndescription: "Use when: \'scan <X>\'."\n---\n'
write_skill long/SKILL.md "$(printf -- '---\ndescription: %s\n---\n' "$(printf 'b%.0s' {1..1025})")"
write_skill empty/SKILL.md $'---\nname: empty\n---\n'
write_skill badname/SKILL.md $'---\nname: Claude_Helper\ndescription: fine\n---\n'
write_skill good/reference/skill.md $'# Not a skill\n'
write_skill commented/SKILL.md $'---\nname: commented-name # migration note\ndescription: | # note\n  Literal text.\n---\n'
write_skill indented/SKILL.md $'---\ndescription: |-2\n  Indented literal.\n---\n'
write_skill emptyblock/SKILL.md $'---\ndescription: >-2\n---\n'
write_skill quotedcomment/SKILL.md $'---\nname: "quoted-name" # note\ndescription: "Use when X, # not a comment." # note <tag>\n---\n'
out="$(run_fixture)"
if grep -qE '^- .*angle.SKILL.md: skill description must not contain < or >' <<<"$out" &&
  grep -qE '^- .*long.SKILL.md: skill description is 1025 characters' <<<"$out" &&
  grep -qE '^- .*empty.SKILL.md: skill description must not be empty' <<<"$out" &&
  grep -qE '^- .*badname.SKILL.md: skill name "Claude_Helper"' <<<"$out" &&
  grep -qE '^- .*reference.skill.md: a file named SKILL.md must start with YAML frontmatter' <<<"$out" &&
  grep -qE '^- .*emptyblock.SKILL.md: skill description must not be empty' <<<"$out" &&
  ! grep -qE 'good.SKILL.md|commented.SKILL.md|indented.SKILL.md|quotedcomment.SKILL.md' <<<"$out"; then
  ok "skill description, name and frontmatter limits fail per file, and a conforming skill passes"
else
  fail "skill limits should fail per file: $out"
fi

reset_fixture
cp "$SCRIPT_DIR/org-agnosticism-tokens.txt" "$TMP/scripts/"
write_plugin_manifest autonomy ''
mkdir -p "$TMP/.changes/autonomy"
printf -- '---\nbump: patch\n---\n\n- Fixed ([#1](https://github.com/melodic-software/x/issues/1)).\n' \
  >"$TMP/.changes/autonomy/linked.md"
printf -- '---\nbump: patch\n---\n\n- Fixed (#1).\n' >"$TMP/.changes/autonomy/bare.md"
out="$(run_fixture)"
if grep -qE '^- \.changes.autonomy.linked\.md: autonomy plugin must not name the org' <<<"$out" &&
  ! grep -q 'bare\.md' <<<"$out"; then
  ok "an autonomy fragment naming the org fails, and a bare issue reference passes"
else
  fail "an autonomy fragment naming the org should fail: $out"
fi
rm -rf "$TMP/.changes" "$TMP/scripts/org-agnosticism-tokens.txt"

ANCHOR_FIX='link the section the pointer rests on'
write_anchor_file() {
  mkdir -p "$(dirname "$TMP/plugins/anchorfix/$1")"
  printf '%s\n' "$2" >"$TMP/plugins/anchorfix/$1"
}
reset_fixture
write_plugin_manifest anchorfix ''
write_anchor_file skills/pointer/SKILL.md $'---\ndescription: "Fixture."\n---\nSee [hooks](https://code.claude.com/docs/en/hooks).\nRead https://git-scm.com/docs/git-config.'
write_anchor_file agents/helper.md $'---\nmodel: sonnet\n---\nRead <https://docs.github.com/en/actions/reference/limits>.'
write_anchor_file skills/clean/SKILL.md $'---\ndescription: "Fixture."\n---\nSee [hooks](https://code.claude.com/docs/en/hooks#hook-events), [#1](https://github.com/anthropics/claude-code/issues/1) and `https://code.claude.com/docs/en/changelog.md`.\nAlso <https://docs.google.com/document/d/x> and (<https://tech.ebu.ch/docs/r/r128.pdf>).'
write_anchor_file skills/clean/evals/fixtures/case.md 'Planted https://code.claude.com/docs/en/hooks link.'
out="$(run_fixture)"
if grep -qF "advisory: plugins/anchorfix/skills/pointer/SKILL.md:4: docs-page link https://code.claude.com/docs/en/hooks has no section anchor; $ANCHOR_FIX (https://code.claude.com/docs/en/hooks#<section>)" <<<"$out" &&
  grep -qF "advisory: plugins/anchorfix/skills/pointer/SKILL.md:5: docs-page link https://git-scm.com/docs/git-config has no section anchor; $ANCHOR_FIX (https://git-scm.com/docs/git-config#<section>)" <<<"$out" &&
  grep -qF "advisory: plugins/anchorfix/agents/helper.md:4: docs-page link https://docs.github.com/en/actions/reference/limits has no section anchor; $ANCHOR_FIX" <<<"$out" &&
  ! grep -qE '^- .*(docs-anchor-baseline|anchorfix/(skills|agents)/)' <<<"$out"; then
  ok "an anchorless docs-page link in a skill or agent file prints an advisory naming the fix, without trailing punctuation, and fails nothing"
else
  fail "an anchorless docs-page link should print an advisory naming the fix, without a failure: $out"
fi
if grep -q 'advisory: plugins/anchorfix/skills/clean/' <<<"$out"; then
  fail "an anchored docs link, an issue link, a code-span URL, a Google Docs document, a PDF and a fixture file should draw no advisory: $out"
else
  ok "an anchored docs link, an issue link, a code-span URL, a Google Docs document, a PDF and a fixture file draw no advisory"
fi

mkdir -p "$TMP/scripts"
printf '%s\n' '# fixture baseline' 'plugins/anchorfix/skills/pointer/SKILL.md 2' \
  'plugins/anchorfix/agents/helper.md 2 # one link anchored since' 'plugins/anchorfix/skills/clean/SKILL.md 1' \
  'not-a-row' >"$TMP/scripts/docs-anchor-baseline.txt"
out="$(run_fixture)"
if ! grep -q 'advisory: plugins/anchorfix/' <<<"$out" &&
  has_fail_line 'stale row for plugins/anchorfix/agents/helper.md: 1 line\(s\) carry an anchorless docs-page link, not 2; lower the row to 1' &&
  has_fail_line 'stale row for plugins/anchorfix/skills/clean/SKILL.md: it has no anchorless docs-page link now; remove the row' &&
  has_fail_line 'malformed row, want `<path> <count>`: not-a-row' &&
  ! grep -q 'stale row for plugins/anchorfix/skills/pointer/' <<<"$out"; then
  ok "a baseline row holding a file's count silences it, and a row above the count or a malformed row fails"
else
  fail "the docs-anchor baseline should silence held counts and fail stale or malformed rows: $out"
fi
rm -f "$TMP/scripts/docs-anchor-baseline.txt"

test_harness::report
