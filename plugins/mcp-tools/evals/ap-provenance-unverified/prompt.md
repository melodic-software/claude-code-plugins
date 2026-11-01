---
description: "The checklist's own P3 worked case: unscoped postmark-mcp is named for a vendor that does not publish it, so P3 is WARN, labeled unverified because the operator did not ask for a registry lookup, and no registry is queried."
tags: [mcp-tools, audit-posture, outcome, provenance, unverified-label, never-fetch, ap-2]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read]
expected_outcome: "postmark (postmark-mcp, unscoped) gets P3 WARN labeled unverified; no npm, curl, pip or other lookup or server run happens."
---

/mcp-tools:audit-posture --config configs/mail.mcp.json

Support wants these two servers for email and error tracking. Anything off about where they come from?
