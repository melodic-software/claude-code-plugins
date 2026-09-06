#!/usr/bin/env bash
# Contract test for where this plugin's artifacts live.
#
# The defect this exists to catch is silent. `audit`, `realign`, and `delta`
# each resolve a home from prose, and `delta` both READS and WRITES the
# comparison baseline. A read path and a write path that name different slots
# raise no error anywhere: the lane deposits a baseline nobody reads and then
# reports "no baseline, this run establishes one" forever, which is exactly what
# a healthy first run looks like. Nothing in the report distinguishes them.
#
# So the assertions below pin ONE canonical home and ONE canonical baseline path
# across every shipped surface, and fail when any surface names a second one.
# They also pin the retirement of the pre-0.12.0 `${CLAUDE_PLUGIN_DATA}` state
# key, whose worktree-path hash was the reason a second checkout of one
# repository never saw the first one's operator decisions.
#
# CHANGELOG.md is excluded from every content sweep on purpose: it is the
# historical record, it quotes the wording it is retiring, and rewriting a
# shipped entry to satisfy a tripwire is the failure mode this file exists to
# make expensive. reference/artifact-protocol.md is excluded from the
# second-slot sweep for a different reason: it is a byte-identical copy of
# docs/PLUGIN-ARTIFACT-PROTOCOL.md, enforced by
# scripts/validate-plugin-contracts.mjs, so this plugin may not edit it.
#
# SC2016 is disabled file-wide on purpose. Single-quoted `${CLAUDE_PLUGIN_DATA}`
# strings below are literal prose under test, never expansions.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BINDING="$PLUGIN_ROOT/reference/topic-docs.md"
CONTRACT="$PLUGIN_ROOT/context/findings-artifact.md"
DELTA="$PLUGIN_ROOT/skills/delta/SKILL.md"

# The two paths every surface must agree on, and the only ones.
HOME_PATH='.work/instruction-placement/<branch-slug>/'
FINDINGS_LEAF='findings.md'
BASELINE_LEAF='baselines/delta-baseline.md'

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# surface — every shipped instruction file in the plugin, minus the changelog
# and minus the protocol copy this plugin does not own.
surface() {
  find "$PLUGIN_ROOT" -type f \( -name '*.md' -o -name '*.json' \) \
    ! -name 'CHANGELOG.md' \
    ! -path '*/reference/artifact-protocol.md' \
    ! -path '*/.claude-plugin/*' |
    sort
}

# runtime_surface — the same set minus the binding, which is the ONE document
# allowed to name the retired location, in its "Retired" section, so an operator
# reading it learns where their old artifacts went. Every other surface naming
# it would be a live resolution path.
#
# SC2329: invoked indirectly, by name, through assert_absent's third argument.
# shellcheck disable=SC2329
runtime_surface() {
  surface | grep -v '/reference/topic-docs\.md$'
}

# assert_absent <label> <extended-regex> [surface-fn]
# Fails listing every hit, because the count is the finding.
assert_absent() {
  local label="$1" pattern="$2" scope="${3:-surface}" hits
  hits="$("$scope" | xargs grep -nEI -- "$pattern" 2>/dev/null)"
  if [[ -z "$hits" ]]; then
    pass "$label"
  else
    fail "$label — $(printf '%s\n' "$hits" | wc -l | tr -d ' ') hit(s)"
    printf '%s\n' "$hits" | sed 's|^'"$PLUGIN_ROOT"'/|       |' >&2
  fi
}

# assert_present <label> <file> <fixed-string>
assert_present() {
  local label="$1" file="$2" needle="$3"
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label — ${file#"$PLUGIN_ROOT"/} does not contain: $needle"
  fi
}

echo "=== instruction-placement artifact home ==="

# --- 1. The binding exists and is the single owner of both paths ------------

if [[ -f "$BINDING" ]]; then
  pass "reference/topic-docs.md ships"
else
  fail "reference/topic-docs.md ships — the placement binding is missing"
fi

if [[ -f "$PLUGIN_ROOT/reference/artifact-protocol.md" ]]; then
  pass "reference/artifact-protocol.md ships (lifecycle protocol participant)"
else
  fail "reference/artifact-protocol.md ships (lifecycle protocol participant)"
fi

assert_present "binding names the default home" "$BINDING" "$HOME_PATH"
assert_present "binding names the findings leaf" "$BINDING" "$FINDINGS_LEAF"
assert_present "binding names the baseline slot" "$BINDING" "$BASELINE_LEAF"

# --- 2. Read path and write path name the SAME baseline slot ----------------
#
# This is the assertion the whole file is for. Every mention of the baseline
# anywhere in the shipped surface must be the one canonical path. A write step
# that says `baselines/delta-baseline.md` while the read step says
# `delta-baseline.md` or `spine-baseline.md` fails here and nowhere else.

# Two shapes are consistent with one slot: the bare leaf `delta-baseline.md`
# and any path ending in `baselines/delta-baseline.md`. A mention that is
# neither — a different leaf name, or the right leaf outside the slot — is a
# second slot, and the run that writes one and reads the other says nothing.
baseline_mentions="$(surface | xargs grep -ohE '[A-Za-z0-9_./<>-]*baseline[A-Za-z0-9_.<>-]*\.md' 2>/dev/null | sort -u | grep -v '^$')"
stray_baselines=""
while IFS= read -r mention; do
  [[ -z "$mention" ]] && continue
  [[ "$mention" == "delta-baseline.md" ]] && continue
  [[ "$mention" == *"$BASELINE_LEAF" ]] && continue
  stray_baselines+="$mention"$'\n'
done <<<"$baseline_mentions"
if [[ -z "$stray_baselines" ]]; then
  pass "every baseline path in the shipped surface resolves to $BASELINE_LEAF"
else
  fail "a second baseline path is named; read and write can disagree"
  printf '%s' "$stray_baselines" | sed 's|^|       |' >&2
fi

# The delta skill must name the slot on both sides of the cycle: the step that
# reads it and the step that captures over it.
delta_baseline_hits="$(grep -cF -- "$BASELINE_LEAF" "$DELTA" 2>/dev/null || true)"
if [[ "${delta_baseline_hits:-0}" -ge 2 ]]; then
  pass "delta names $BASELINE_LEAF on both the read and the capture step"
else
  fail "delta names $BASELINE_LEAF ${delta_baseline_hits:-0} time(s); the read step and the capture step must each name it"
fi

assert_present "contract owns the baseline's shape" "$CONTRACT" "## The delta baseline"
assert_present "contract names the same slot" "$CONTRACT" "$BASELINE_LEAF"

# --- 3. The retired state key is gone, with no read-side fallback -----------

if [[ -e "$PLUGIN_ROOT/lib/state-key.sh" ]]; then
  fail "lib/state-key.sh is retired from this plugin but still ships"
else
  pass "lib/state-key.sh no longer ships"
fi

assert_absent "no runtime surface resolves the retired state key" 'state-key\.sh' runtime_surface
assert_absent "no runtime surface composes a plugin-data findings path" 'CLAUDE_PLUGIN_DATA\}?/findings' runtime_surface

assert_present "binding records the retirement, so the move is discoverable" "$BINDING" "## Retired: the plugin-data state key"
assert_present "binding states the old path is not consulted" "$BINDING" "is inert, not read"

# A `Bash(...)` grant for the retired helper would let a skill shell out to a
# copy in some other plugin, which is the fallback the move exists to close.
assert_absent "no allowed-tools grant for the retired helper" 'Bash\(\$\{CLAUDE_PLUGIN_ROOT\}/lib/state-key\.sh'

# --- 4. Every artifact-touching skill routes through the binding ------------

for skill in audit realign delta; do
  path="$PLUGIN_ROOT/skills/$skill/SKILL.md"
  if grep -qF 'reference/topic-docs.md' "$path" 2>/dev/null; then
    pass "$skill routes placement through the binding"
  else
    fail "$skill routes placement through the binding — no reference to reference/topic-docs.md"
  fi
done

# `check` and `setup` place no artifact; a placement reference there would be a
# second reader of a home neither one writes.
for skill in check setup; do
  path="$PLUGIN_ROOT/skills/$skill/SKILL.md"
  if grep -qF 'reference/topic-docs.md' "$path" 2>/dev/null; then
    fail "$skill must not resolve an artifact home — it places nothing"
  else
    pass "$skill places nothing and resolves no home"
  fi
done

echo
if [[ $fails -eq 0 ]]; then
  echo "PASS - artifact home is one slot on every surface"
  exit 0
fi
echo "FAIL - $fails assertion(s)" >&2
exit 1
