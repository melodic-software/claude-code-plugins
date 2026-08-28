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
