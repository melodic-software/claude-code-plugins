---
description: "map-landscape --check against a committed record that has drifted (legacy-reports edge gone, pricing-engine edge new) reports the drift and writes nothing: the committed landscape.json is left as it was and nothing is rendered"
tags: [architecture, map-landscape, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The final reply reports drift naming acme-labs/legacy-reports (removed) and acme-labs/pricing-engine (added). docs/architecture/landscape.json still holds the legacy-reports edge and no pricing-engine edge; no Write or Edit call is made and render-landscape.sh is never run."
---

/architecture:map-landscape --check --out docs/architecture
