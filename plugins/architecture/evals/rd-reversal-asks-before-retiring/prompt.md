---
description: "A decision that reverses an existing record gets a new record naming the old one, and the old record is neither deleted, edited nor moved before the person says yes"
tags: [architecture, record-decision, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The run proposes or writes a new record numbered 0003 that names ADR 0002 and why it was reversed, states the retirement mode (delete by default) and its layer, and ends by asking before retiring 0002. ADR 0002 is not removed, edited or moved."
---

/architecture:record-decision We are reversing ADR 0002: the public API goes back to REST. Context: partners now use three fixed views, and GraphQL query cost made rate limiting unpredictable. We weighed keeping GraphQL with query cost limits and rejected it because partners could not predict their quotas. Consequences: every partner view needs a versioned endpoint, and moving back to GraphQL later means rewriting the partner SDKs.
