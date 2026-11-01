---
description: "Hard because a fixed-looking image tag (:1.4) reads as pinned: the contract says only an @sha256 digest pins a container, so browser is P1 WARN (mutable tag, container launcher) and the digest image PASSes."
tags: [mcp-tools, audit-posture, outcome, floating-version, container, ap-1]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read]
expected_outcome: "browser (ghcr.io/acme/browser-mcp:1.4 via docker) is reported as a mutable tag, not exact, with P1 WARN; search-index (an @sha256 digest) passes P1."
---

/mcp-tools:audit-posture --config configs/containers.mcp.json

We moved two servers into containers last sprint. Are they both pinned now?
