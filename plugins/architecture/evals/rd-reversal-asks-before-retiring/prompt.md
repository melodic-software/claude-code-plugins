---
description: "A decision that reverses an existing record gets a new record naming the old one, the line citing the old record is listed with a proposal, and neither the old record nor the citing file changes before the person says yes"
tags: [architecture, adr, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The run proposes or writes a new record numbered 0003 that names ADR 0002 and why it was reversed, states the retirement mode (delete by default) and its layer, lists `src/api/schema.graphql:1` as a line citing ADR 0002 with a proposal to point it at 0003 or drop it, and ends by asking before retiring 0002. ADR 0002 is not removed, edited or moved, and `src/api/schema.graphql` is not edited."
---

/architecture:adr We are reversing ADR 0002: the public API goes back to REST. Context: partners now use three fixed views, and GraphQL query cost made rate limiting unpredictable. We weighed keeping GraphQL with query cost limits and rejected it because partners could not predict their quotas. Consequences: every partner view needs a versioned endpoint, and moving back to GraphQL later means rewriting the partner SDKs.
