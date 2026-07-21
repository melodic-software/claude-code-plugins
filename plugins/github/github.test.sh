#!/usr/bin/env bash
# Contract test for the github plugin's durable invariants:
#   - D4 zero-vendored-knowledge: no baked endpoints, no shipped scope tables, no prices
#   - agnostic conformance: no publisher/org/tool assumptions in prose (plugin.json author is
#     the sanctioned exception)
#   - area-coverage oracle: reference/areas.md rows match the canonical Brief coverage list
#     (fixture lives here, independent of the file it checks)
#   - recipe non-hollow contract: every primary-tier recipe carries the six contract sections
#     and a >=10-question audit checklist
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AREAS="$PLUGIN_DIR/reference/areas.md"
RECIPES_DIR="$PLUGIN_DIR/reference/recipes"

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

# --- D4 sweep: no baked endpoints anywhere in the plugin --------------------
# This file holds the very patterns it hunts, so the tree sweeps exclude it.
SELF_EXCLUDE=(--exclude="$(basename "${BASH_SOURCE[0]}")")
hits=$(grep -rEn "${SELF_EXCLUDE[@]}" "api\.github\.com|/orgs/\{|/repos/\{|/enterprises/" "$PLUGIN_DIR" || true)
if [[ -z "$hits" ]]; then
  ok "D4: no baked API endpoints"
else
  fail "D4 endpoint pattern found:"$'\n'"$hits"
fi

# --- D4 sweep: no dollar prices anywhere in the plugin ----------------------
hits=$(grep -rEn "${SELF_EXCLUDE[@]}" '\$[0-9]' "$PLUGIN_DIR" || true)
if [[ -z "$hits" ]]; then
  ok "D4: no shipped prices"
else
  fail "D4 price pattern found:"$'\n'"$hits"
fi

# --- D4 sweep: no scope names shipped as guidance ---------------------------
# Scope tokens in shipped prose (*.md) would be a vendored mechanics table; eval
# scenario prompts (*.json) may legitimately posit a scope by name.
hits=$(grep -r -E -i -n "admin:(org|enterprise)|read:(org|user|packages)|write:(org|packages)|manage_billing|repo:status" \
  "$PLUGIN_DIR" --include='*.md' || true)
if [[ -z "$hits" ]]; then
  ok "D4: no scope names in shipped prose"
else
  fail "scope token in shipped prose:"$'\n'"$hits"
fi

# --- agnostic conformance: no publisher/org/tool assumptions in prose -------
# plugin.json author metadata is the sanctioned exception (json excluded by the glob).
hits=$(grep -riEn "melodic|medley|github-iac|pulumi" "$PLUGIN_DIR" --include='*.md' || true)
if [[ -z "$hits" ]]; then
  ok "agnosticism: no publisher/org/tool assumptions in prose"
else
  fail "agnosticism violation:"$'\n'"$hits"
fi

# --- area-coverage oracle ---------------------------------------------------
# Canonical area keys from the Brief coverage matrix. This fixture is the
# independent source the router rows are diffed against — update it only when
# the Brief's coverage list changes.
canonical_areas=(
  rulesets
  custom-properties
  billing
  security-model
  codespaces
  cloud-sandboxes
  projects-and-issues
  actions
  webhooks
  discussions
  packages
  pages
  hosted-compute-networking
  authentication-security
  advanced-security
  code-quality
  deploy-keys
  compliance
  verified-domains
  secrets-and-variables
  github-apps
  oauth-app-policy
  personal-access-tokens
  scheduled-reminders
  archive-logs
  deleted-repositories
  developer-settings
)

if [[ ! -f "$AREAS" ]]; then
  fail "missing $AREAS"
else
  # Router rows are "| `key` | tier | ..." — extract the backticked key column.
  # shellcheck disable=SC2016  # literal backtick/$ in the patterns, no expansion wanted
  mapfile -t router_areas < <(grep -oE '^\| `[a-z0-9-]+`' "$AREAS" | sed 's/^| `//; s/`$//' | sort)
  mapfile -t expected < <(printf '%s\n' "${canonical_areas[@]}" | sort)
  diff_out=$(diff <(printf '%s\n' "${expected[@]}") <(printf '%s\n' "${router_areas[@]}") || true)
  if [[ -z "$diff_out" ]]; then
    ok "area oracle: areas.md rows match the ${#canonical_areas[@]} canonical keys exactly"
  else
    fail "area oracle mismatch (canonical vs areas.md):"$'\n'"$diff_out"
  fi
fi

# --- recipe non-hollow contract ---------------------------------------------
recipes=(billing.md security-posture.md rulesets-repo-drift.md actions-policy.md)
fixed_headings=(
  "## Credential-and-gate preflight"
  "## Audit-question checklist"
  "## Drift comparison against declared conventions"
  "## Dated caveats (re-verify live)"
  "## Doc pointers"
)
for r in "${recipes[@]}"; do
  f="$RECIPES_DIR/$r"
  if [[ ! -f "$f" ]]; then
    fail "missing recipe $r"
    continue
  fi
  for h in "${fixed_headings[@]}"; do
    if grep -qF "$h" "$f"; then
      ok "$r carries '$h'"
    else
      fail "$r missing heading '$h'"
    fi
  done
  # Sixth section is area-shaped: cost levers (billing) or posture heuristics.
  if grep -qE "^## (Cost-control levers|Posture heuristics)$" "$f"; then
    ok "$r carries a levers/heuristics section"
  else
    fail "$r missing '## Cost-control levers' or '## Posture heuristics'"
  fi
  # Checklist depth: >=10 numbered questions between the checklist heading and
  # the next H2 (wrapped lines: count only list-starting lines).
  qcount=$(awk '/^## Audit-question checklist$/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\./{n++} END{print n+0}' "$f")
  if [[ "$qcount" -ge 10 ]]; then
    ok "$r checklist has $qcount questions (>=10)"
  else
    fail "$r checklist has only $qcount numbered questions (<10)"
  fi
done

# --- evals present for every judgment-bearing skill -------------------------
for s in audit advise setup; do
  e="$PLUGIN_DIR/skills/$s/evals/evals.json"
  if [[ -f "$e" ]] && grep -q '"skill_name"' "$e"; then
    ok "evals present for $s"
  else
    fail "missing or malformed evals for $s ($e)"
  fi
done

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
