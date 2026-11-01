#!/usr/bin/env bash
# The setup-repo team layer plus a tracked .claude/provenance.json, the retired team config
# name (retirements.yaml record attribution-r001), still setting stamp_expiry_days.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/setup-repo.sh"
mkdir -p .claude
cat >.claude/provenance.json <<'JSON'
{
  "stamp_expiry_days": 45
}
JSON
git add .claude/provenance.json
git -c user.name=eval -c user.email=eval@example.invalid commit -qm "chore: provenance config"
