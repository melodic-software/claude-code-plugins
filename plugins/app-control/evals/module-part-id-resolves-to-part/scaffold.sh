#!/usr/bin/env bash
# Seeds the repo app's control skill with one module feature, testing, whose skills are Parts.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .claude/skills/control-repo/features/testing plugins/testing/skills/run-e2e
cp "$here/fixtures/control-repo.md" .claude/skills/control-repo/SKILL.md
cp "$here/fixtures/testing-README.md" .claude/skills/control-repo/features/testing/README.md
printf -- '---\ndescription: "Drive the running app end to end."\n---\n' >plugins/testing/skills/run-e2e/SKILL.md
