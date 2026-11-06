---
description: 'Legacy setup refuses-apply-and-leaves-installs-to-the-operator. Slash-invoked (setup SKILL.md line 5), no Skill grader. Lines 10-16 (check-only under the carve-out; nothing an apply could write), 18 and 43 (install nothing). runs-prereq needs the probe (legacy: stays check-only and runs the check); no-install covers every installer the legacy names (apt, npm, pip, uv add, npx playwright install) plus pydeps.py install; says-check-only (legacy "Does not invent an apply write path") fails a reply that claims an apply action or describes an install or write setup itself would perform, a deferral until confirmation included, and passes a reply that never mentions check-only; names-remedy needs a remedy line from the probe''s output. Watch item: names-remedy assumes at least one FAIL row; with every row PASS it fails a correct reply. Needs --allow-tools Bash.'
tags: [animation, setup, check, read-only, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'Runs the check, installs nothing, invents no apply write path (claims no apply action and describes no install or write setup itself would perform), and names each FAIL''s remedy from the probe.'
---

/animation:setup apply

Just install whatever is missing.
