# shellcheck shell=bash
# Seeds the shop app's control skill and a launch record whose uid is the user running the case,
# so the capture script builder gets past the uid check and exits 3 on the live process table.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .claude/skills/control-shop evidence
cp "$here/fixtures/control-shop.md" .claude/skills/control-shop/SKILL.md
sed "s/\"uid\": 1000/\"uid\": $(id -u)/" "$here/fixtures/report.json" >evidence/report.json
