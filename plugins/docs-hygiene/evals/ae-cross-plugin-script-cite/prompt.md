---
description: "Hard. In a two-plugin marketplace, release-kit's ship skill path-cites lint-kit's scripts/run-checks.sh, and the repo's CI workflow runs the same script. The contract makes the same path illegal from another plugin (cross-plugin cites go through the slash invocation) and legal from CI (scripts/ entry surface). Install recipes naming the plugins@marketplace id are legal. A no-skill model flags both script cites or neither. Written from the before SKILL.md contract."
tags: [hard, audit-encapsulation, outcome, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Reports one violation: plugins/release-kit/skills/ship/SKILL.md citing plugins/lint-kit/skills/check/scripts/run-checks.sh, to be routed through the lint-kit check skill's slash invocation. Treats the .github/workflows/ci.yml call to the same script and the `claude plugin install ...@acme-tools` lines as legal."
---

We're about to publish lint-kit and release-kit from our acme-tools marketplace as separate installs. Look across the whole repo and tell me whether anything depends on another plugin's skill files in a way that won't hold once someone installs only one of them.
