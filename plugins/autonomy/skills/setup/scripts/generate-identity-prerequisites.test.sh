#!/usr/bin/env bash
# Unit tests for generate-identity-prerequisites.mjs. Cases are named in the
# co-located manifest; this harness builds throwaway trees where needed and
# drives generate / --check / drift / leaf↔emission parity.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR="$SELF_DIR/generate-identity-prerequisites.mjs"
MANIFEST="$SELF_DIR/generate-identity-prerequisites.test.manifest.json"
PLUGIN_ROOT="$(cd "$SELF_DIR/../../.." && pwd)"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "FAIL: missing test manifest $MANIFEST" >&2
  exit 1
fi

# --- case: generate_and_check_clean -----------------------------------------
OUT="$(node "$GENERATOR" --check 2>&1)"
CODE=$?
if [[ $CODE -eq 0 ]]; then
  ok "generate_and_check_clean: --check exits 0 on committed emission"
else
  fail "generate_and_check_clean: --check failed ($CODE): $OUT"
fi

# --- case: drift_fixture ----------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/reference/routines" "$tmp/generated" "$tmp/skills/setup/scripts"
# Minimal leaf pair so the generator can run under --root.
cat >"$tmp/reference/routines/alpha.md" <<'EOF'
# alpha

## Prerequisites

Single-posture identity: `alpha` (bare class token).

| Axis | Value |
|---|---|
| Access class | `repo` |
| Isolation floor | `L2` — cited |
| Connector entitlements | none — `repo` access |
| Connector entitlement rung | n/a (no connector). For `prod` / `product` / `org` / `ext`, entitlement binds at the Org binding layer |
| `executor_class` merge cap | cited from security-binding |
| Repo needs | tracker binding via the work-item tracker seam (`.work-item-tracker.json` + adapter `capabilities.json`); absent is `unsupported` |
EOF

# Seed a correct emission, then hand-edit it.
if ! node "$GENERATOR" --root "$tmp" >/dev/null 2>"$tmp/gen.err"; then
  fail "drift_fixture: initial generate failed: $(cat "$tmp/gen.err")"
else
  # Hand-edit: drop a need so the emission drifts from the leaf.
  node -e '
    const fs = require("node:fs");
    const p = process.argv[1];
    const e = JSON.parse(fs.readFileSync(p, "utf8"));
    e.identities[0].needs = [];
    fs.writeFileSync(p, JSON.stringify(e, null, 2) + "\n");
  ' "$tmp/generated/identity-prerequisites.json"
  if node "$GENERATOR" --root "$tmp" --check >/dev/null 2>"$tmp/check.err"; then
    fail "drift_fixture: --check should exit non-zero on hand-edited emission"
  else
    ok "drift_fixture: --check exits non-zero on hand-edited emission"
  fi
  # Regenerating restores sync.
  node "$GENERATOR" --root "$tmp" >/dev/null
  if node "$GENERATOR" --root "$tmp" --check >/dev/null 2>"$tmp/check2.err"; then
    ok "drift_fixture: regenerated emission passes --check"
  else
    fail "drift_fixture: regenerated --check failed: $(cat "$tmp/check2.err")"
  fi
fi

# --- case: leaf_emission_parity ---------------------------------------------
parity_out="$(node -e '
const fs = require("node:fs");
const path = require("node:path");
const leavesDir = path.join(process.argv[1], "reference", "routines");
const emission = JSON.parse(fs.readFileSync(
  path.join(process.argv[1], "generated", "identity-prerequisites.json"), "utf8"));
const leafIds = new Set();
for (const name of fs.readdirSync(leavesDir).filter((n) => n.endsWith(".md"))) {
  const text = fs.readFileSync(path.join(leavesDir, name), "utf8");
  const start = text.search(/^## Prerequisites\s*$/m);
  if (start < 0) { console.error("missing Prerequisites in " + name); process.exit(1); }
  const after = text.slice(start);
  const endRel = after.slice(after.indexOf("\n") + 1).search(/^## /m);
  const section = endRel < 0 ? after : after.slice(0, after.indexOf("\n") + 1 + endRel);
  const headings = [...section.matchAll(/^### `([^`]+)`\s*$/gm)].map((m) => m[1]);
  if (headings.length) headings.forEach((id) => leafIds.add(id));
  else {
    const m = section.match(/Single-posture identity:\s*`([^`]+)`/);
    if (!m) { console.error("no identity in " + name); process.exit(1); }
    leafIds.add(m[1]);
  }
}
const emitted = new Set(emission.identities.map((i) => i.identity));
const missing = [...leafIds].filter((id) => !emitted.has(id)).sort();
const extra = [...emitted].filter((id) => !leafIds.has(id)).sort();
if (missing.length || extra.length) {
  console.error(JSON.stringify({ missing, extra }));
  process.exit(1);
}
console.log([...emitted].sort().join(","));
' "$PLUGIN_ROOT" 2>"$tmp/parity.err")"
parity_code=$?
if [[ $parity_code -eq 0 ]]; then
  ok "leaf_emission_parity: leaf identities ↔ emission ($parity_out)"
else
  fail "leaf_emission_parity: $(cat "$tmp/parity.err")"
fi

# --- case: posture_divergence -----------------------------------------------
div="$(node -e '
const e = require(process.argv[1]);
const mech = e.identities.find((i) => i.identity === "dependency-update-wave/mechanical");
const chg = e.identities.find((i) => i.identity === "dependency-update-wave/changelog-informed");
if (!mech || !chg) { console.error("missing dependency-update-wave postures"); process.exit(1); }
if (mech.isolation_floor === chg.isolation_floor) {
  console.error("floors should diverge: " + mech.isolation_floor);
  process.exit(1);
}
const mechNeeds = mech.needs.map((n) => n.id).join(",");
const chgNeeds = chg.needs.map((n) => n.id).join(",");
if (mechNeeds === chgNeeds) {
  console.error("needs should diverge");
  process.exit(1);
}
if (!chg.needs.some((n) => n.id === "upstream_changelog")) {
  console.error("changelog-informed missing upstream_changelog");
  process.exit(1);
}
console.log(mech.isolation_floor + " vs " + chg.isolation_floor);
' "$PLUGIN_ROOT/generated/identity-prerequisites.json" 2>"$tmp/div.err")"
div_code=$?
if [[ $div_code -eq 0 ]]; then
  ok "posture_divergence: dependency-update-wave floors/needs differ ($div)"
else
  fail "posture_divergence: $(cat "$tmp/div.err")"
fi

# Manifest case names must stay honest — every named case ran above.
expected_cases="$(node -e 'const m=require(process.argv[1]); console.log(m.cases.join("\n"))' "$MANIFEST")"
for case_name in $expected_cases; do
  case "$case_name" in
    generate_and_check_clean|drift_fixture|leaf_emission_parity|posture_divergence) ;;
    *) fail "manifest names unknown case: $case_name" ;;
  esac
done
ok "manifest_cases: $(echo "$expected_cases" | wc -l | tr -d ' ') named cases exercised"

echo
echo "Passed: $PASS  Failed: $FAIL"
if [[ $FAIL -ne 0 ]]; then
  exit 1
fi
exit 0
