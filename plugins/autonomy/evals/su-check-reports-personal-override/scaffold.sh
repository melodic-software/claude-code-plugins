#!/usr/bin/env bash
# A solo-adopter checkout with a tracked project binding (budget_posture free) and an ignored
# personal override beside it that refines budget_posture to paid-opt-in. No org_policy_home pointer.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p .claude/autonomy
cat >.claude/autonomy/binding.json <<'JSON'
{
  "schema_version": "1.0",
  "roles": {
    "capability-distribution-home": null,
    "ci-orchestration-home": null,
    "settings-as-code-home": null,
    "org-policy-home": null,
    "runner-execution-home": null
  },
  "org_policy_home": null,
  "budget_posture": "free",
  "substrate": {
    "local-machine": true,
    "ci-runners": false,
    "self-run-infrastructure": false
  }
}
JSON

cat >.claude/autonomy/binding.local.json <<'JSON'
{
  "budget_posture": "paid-opt-in"
}
JSON

printf '%s\n' '.claude/**/*.local.*' >.gitignore
printf '# widget\n\nA small widget library.\n' >README.md
git add .
git commit -q -m "chore: scaffold widget with autonomy binding"
