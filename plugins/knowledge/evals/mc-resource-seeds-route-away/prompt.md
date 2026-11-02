---
description: "Reaches map-corpus Phase 1 'Resource seed' rule (a resource-seeds-only corpus has no discovery basis and routes to direct /knowledge:docpage-digest runs): two raw-file seeds and no origin or repository seed. The reply names /knowledge:docpage-digest and the missing origin seed or discovery basis, runs no llms.txt, sitemap, or robots.txt discovery, and writes no link map, manifest, inventory, queue, or handoff. Skill is not granted, so the hand-off is named in the reply rather than invoked."
tags: [knowledge, map-corpus, outcome, routing]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply routes the two URLs to /knowledge:docpage-digest and says the mapper needs an origin seed or another discovery basis. No Bash command touches llms.txt, a sitemap, or robots.txt, and no Write creates link-map.json, queue.json, manifest.json, inventory.json, or mapper-handoff.md."
---

/knowledge:map-corpus retry-spec https://raw.githubusercontent.com/example-org/retry-spec/main/SPEC.md https://raw.githubusercontent.com/example-org/retry-spec/main/README.md
