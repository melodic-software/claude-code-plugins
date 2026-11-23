#!/usr/bin/env bash
# test-scope: plugins/github/*
set -uo pipefail

[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || {
  echo "SKIP: bash 4+ required (mapfile)" >&2
  exit 0
}

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

sweep() {
  local ok_msg="$1" fail_msg="$2" hits
  shift 2
  hits=$(grep "$@" || true)
  if [[ -z "$hits" ]]; then
    ok "$ok_msg"
  else
    fail "$fail_msg"$'\n'"$hits"
  fi
}

SELF_EXCLUDE=(--exclude="$(basename "${BASH_SOURCE[0]}")")
sweep "D4: no baked API endpoints" "D4 endpoint pattern found:" \
  -rEn "${SELF_EXCLUDE[@]}" "api\.github\.com|/orgs/\{|/repos/\{|/enterprises/" "$PLUGIN_DIR"

sweep "D4: no shipped prices" "D4 price pattern found:" \
  -rEn "${SELF_EXCLUDE[@]}" '\$[0-9]' "$PLUGIN_DIR"

sweep "D4: no scope names in shipped prose" "scope token in shipped prose:" \
  -r -E -i -n "admin:(org|enterprise)|read:(org|user|packages)|write:(org|packages)|manage_billing|repo:status" \
  "$PLUGIN_DIR" --include='*.md'

hits=$(grep -riEn "melodic|medley|github-iac|pulumi" "$PLUGIN_DIR" --include='*.md' || true)
if [[ -z "$hits" ]]; then
  ok "agnosticism: no publisher/org/tool assumptions in prose"
else
  fail "agnosticism violation:"$'\n'"$hits"
fi

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
  # shellcheck disable=SC2016  # literal backtick/$ in the patterns, no expansion wanted
  mapfile -t router_areas < <(grep -oE '^\| `[a-z0-9-]+`' "$AREAS" | sed 's/^| `//; s/`$//' | sort)
  diff_out=$(diff <(printf '%s\n' "${canonical_areas[@]}" | sort) <(printf '%s\n' "${router_areas[@]}") || true)
  if [[ -z "$diff_out" ]]; then
    ok "area oracle: areas.md rows match the ${#canonical_areas[@]} canonical keys exactly"
  else
    fail "area oracle mismatch (canonical vs areas.md):"$'\n'"$diff_out"
  fi
fi

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
  if grep -qE "^## (Cost-control levers|Posture heuristics)$" "$f"; then
    ok "$r carries a levers/heuristics section"
  else
    fail "$r missing '## Cost-control levers' or '## Posture heuristics'"
  fi
  qcount=$(awk '/^## Audit-question checklist$/{flag=1; next} /^## /{flag=0} flag && /^[0-9]+\./{n++} END{print n+0}' "$f")
  if [[ "$qcount" -ge 10 ]]; then
    ok "$r checklist has $qcount questions (>=10)"
  else
    fail "$r checklist has only $qcount numbered questions (<10)"
  fi
done

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
