---
description: "Legacy reuse-or-replace 5. A new cross-service communication pattern beside the message bus, with no recorded reason. adr-required and migrate-or-retire are regex; adr-not-commit-note (llm) quotes legacy expectations 1-3. Read-only."
tags: [discipline, reuse-or-replace, outcome, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Classifies the divergence as architectural, so its rationale belongs in an ADR, not a commit or PR note; flags the unrecorded second way; and requires migrating and retiring the message bus if the new pattern supersedes it."
---

/discipline:reuse-or-replace I'm introducing a whole new architectural pattern for how our services talk to each other, different from the existing message-bus approach, and I'll just start using it in this one service.
