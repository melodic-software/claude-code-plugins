---
description: "Legacy recheck-against-upstream 2. A dependency pinned by an ADR; the run has no network, so the prompt gives the upstream changelog and issue state fetched this session as data, and they show the incompatibility unfixed. deliberate-classified and rationale-still-holds are regex; recheck-not-revert (llm) quotes legacy expectations 1-3. Read-only."
tags: [discipline, recheck-against-upstream, outcome, narration, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Classifies the pin as a deliberate divergence, re-checks the ADR's rationale against the given upstream state, finds it still holds, keeps the pin and reports clean."
---

/discipline:recheck-against-upstream we pin this dependency to an old version on purpose; there's an ADR explaining the incompatibility that forced it.

The pin is `"pg": "8.7.3"` in package.json. ADR 0007 (accepted 2025-03-04) says pg 8.8.0 made `pool.end()` hang while a client is checked out, which breaks our graceful shutdown, so we pin 8.7.3 until upstream issue 2851 is fixed.

I fetched these this session; treat them as the current upstream state:

- pg's latest release is 8.13.1. Its changelog from 8.8.0 through 8.13.1 has no entry about `pool.end()` or issue 2851.
- Issue 2851 is open. Its newest comment (2026-10-02) reports the hang on 8.13.0 with a reproduction script.
